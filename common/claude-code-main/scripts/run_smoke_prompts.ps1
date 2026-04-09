param(
  [string]$WorkspacePath = "",
  [string]$OutDir = "",
  [string[]]$Only = @(),
  [int]$TimeoutSeconds = 300,
  [switch]$DisableMcp,
  [int]$RetryAttempts = 2,
  [int]$RetryBackoffSeconds = 5,
  [switch]$FailOnAnyFailure
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $OutDir = Join-Path $PSScriptRoot "..\tmp_smoke\runs"
}
$resolvedOutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null

function Read-InstallWorkspacePath {
  $installReceiptPath = Join-Path $env:USERPROFILE ".agents\plugins\last-global-install.json"
  if (-not (Test-Path -LiteralPath $installReceiptPath)) {
    return ""
  }
  try {
    $obj = Get-Content -LiteralPath $installReceiptPath -Raw | ConvertFrom-Json
    $value = [string]$obj.workspace_path
    if ([string]::IsNullOrWhiteSpace($value)) {
      return ""
    }
    return [System.IO.Path]::GetFullPath($value)
  }
  catch {
    return ""
  }
}

function Resolve-WorkspacePath {
  param([string]$ExplicitPath)
  if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
    return [System.IO.Path]::GetFullPath($ExplicitPath)
  }
  if (-not [string]::IsNullOrWhiteSpace($env:CODEX_WORKSPACE_PATH)) {
    return [System.IO.Path]::GetFullPath($env:CODEX_WORKSPACE_PATH)
  }
  if (-not [string]::IsNullOrWhiteSpace($env:CODEX_WORKSPACE)) {
    return [System.IO.Path]::GetFullPath($env:CODEX_WORKSPACE)
  }
  $fromInstall = Read-InstallWorkspacePath
  if (-not [string]::IsNullOrWhiteSpace($fromInstall)) {
    return $fromInstall
  }
  return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

$WorkspacePath = Resolve-WorkspacePath -ExplicitPath $WorkspacePath
if (-not (Test-Path -LiteralPath $WorkspacePath)) {
  throw "WorkspacePath not found: $WorkspacePath"
}
if ($RetryAttempts -lt 1) {
  $RetryAttempts = 1
}

$allCases = @(
  [pscustomobject]@{
    id = "workspace-core"
    prompt = "Scan this repository, summarize current workspace status, and list the top risks before coding. Do not modify files."
    keywords = @("workspace", "status", "risk", "repository", "context")
    minHits = 2
  },
  [pscustomobject]@{
    id = "git-review"
    prompt = "Summarize the recent changes in this repo and prepare a clean commit plan. Do not modify files."
    keywords = @("commit", "changes", "diff", "plan", "review")
    minHits = 2
  },
  [pscustomobject]@{
    id = "agent-orchestration"
    prompt = "Break this feature delivery into a planner/executor workflow with milestones and verification gates. Do not modify files."
    keywords = @("planner", "executor", "milestone", "verification", "phase", "gate")
    minHits = 3
  },
  [pscustomobject]@{
    id = "integration-runtime"
    prompt = "Inspect runtime integrations and list MCP-backed capabilities available in this environment. Do not modify files."
    keywords = @("mcp", "playwright", "filesystem", "fetch", "git", "github", "integration")
    minHits = 4
  },
  [pscustomobject]@{
    id = "personal-productivity"
    prompt = "Review this implementation approach, identify likely failure points, and give a lightweight verify/debug loop. Do not modify files."
    keywords = @("failure", "verify", "debug", "loop", "risk", "check")
    minHits = 3
  }
)

if ($Only.Count -gt 0) {
  $normalizedOnly = @()
  foreach ($entry in $Only) {
    foreach ($part in ([string]$entry -split ",")) {
      $value = $part.ToLowerInvariant().Trim()
      if (-not [string]::IsNullOrWhiteSpace($value)) {
        $normalizedOnly += $value
      }
    }
  }
  $cases = @($allCases | Where-Object { $normalizedOnly -contains $_.id.ToLowerInvariant() })
  if ($cases.Count -eq 0) {
    throw "No valid case matched -Only. Allowed values: $($allCases.id -join ', ')"
  }
} else {
  $cases = $allCases
}

function Get-KeywordHitCount {
  param(
    [string]$Text,
    [string[]]$Keywords
  )

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return 0
  }

  $textLower = $Text.ToLowerInvariant()
  $hits = 0
  foreach ($kw in $Keywords) {
    if ($textLower.Contains($kw.ToLowerInvariant())) {
      $hits++
    }
  }
  return $hits
}

function Write-Utf8NoBomText {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Append-Utf8NoBomText {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$AppendContent
  )
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::AppendAllText($Path, $AppendContent, $utf8NoBom)
}

function Resolve-CodexPath {
  if (-not [string]::IsNullOrWhiteSpace($env:CODEX_BIN) -and (Test-Path -LiteralPath $env:CODEX_BIN)) {
    return $env:CODEX_BIN
  }

  try {
    $cmd = Get-Command codex -ErrorAction Stop
    if ($cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source)) {
      return $cmd.Source
    }
  }
  catch {}

  $roots = @(
    (Join-Path $env:USERPROFILE ".vscode\extensions"),
    (Join-Path $env:USERPROFILE ".cursor\extensions")
  )

  foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $extDirs = Get-ChildItem -Path $root -Directory -Filter "openai.chatgpt-*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    foreach ($dir in $extDirs) {
      $candidateExe = Join-Path $dir.FullName "bin\windows-x86_64\codex.exe"
      if (Test-Path -LiteralPath $candidateExe) {
        return $candidateExe
      }
    }
  }

  return $null
}

$codexPath = Resolve-CodexPath
if ([string]::IsNullOrWhiteSpace($codexPath)) {
  throw "codex executable not found. Set CODEX_BIN or ensure codex is on PATH."
}

$results = New-Object System.Collections.Generic.List[object]

Write-Host "Running smoke prompts with codex exec..."
Write-Host "Workspace: $WorkspacePath"
Write-Host "Output: $resolvedOutDir"
Write-Host "Cases: $($cases.id -join ', ')"
Write-Host "TimeoutSeconds per case: $TimeoutSeconds"
Write-Host "DisableMcp: $DisableMcp"
Write-Host "RetryAttempts: $RetryAttempts"
Write-Host "RetryBackoffSeconds: $RetryBackoffSeconds"
Write-Host "Codex binary: $codexPath"

foreach ($case in $cases) {
  $id = $case.id
  $stdoutPath = Join-Path $resolvedOutDir ($id + ".stdout.log")
  $stderrPath = Join-Path $resolvedOutDir ($id + ".stderr.log")
  $combinedPath = Join-Path $resolvedOutDir ($id + ".combined.log")
  $lastPath = Join-Path $resolvedOutDir ($id + ".last.txt")

  Remove-Item -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $stderrPath -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $combinedPath -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $lastPath -ErrorAction SilentlyContinue
  Write-Utf8NoBomText -Path $stdoutPath -Content ""
  Write-Utf8NoBomText -Path $stderrPath -Content ""
  Write-Utf8NoBomText -Path $combinedPath -Content ""

  Write-Host ""
  Write-Host "=== Running: $id ===" -ForegroundColor Cyan
  $start = Get-Date

  $caseTimeoutSeconds = $TimeoutSeconds
  if ($caseTimeoutSeconds -lt 90 -and ($id -eq "workspace-core" -or $id -eq "integration-runtime")) {
    $caseTimeoutSeconds = 90
  }

  $attemptsUsed = 0
  $timedOut = $false
  $exitCode = 1
  $hits = 0
  $hasOutput = $false
  $status = "FAIL"

  for ($attempt = 1; $attempt -le $RetryAttempts; $attempt++) {
    $attemptsUsed = $attempt
    $attemptStdoutPath = Join-Path $resolvedOutDir ($id + ".stdout.attempt" + $attempt + ".log")
    $attemptStderrPath = Join-Path $resolvedOutDir ($id + ".stderr.attempt" + $attempt + ".log")
    Remove-Item -LiteralPath $attemptStdoutPath -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $attemptStderrPath -ErrorAction SilentlyContinue

    $escapedPrompt = $case.prompt.Replace('"', '\"')
    $effectiveDisableMcp = $DisableMcp.IsPresent
    if (-not $effectiveDisableMcp -and $id -ne "integration-runtime") {
      $effectiveDisableMcp = $true
    }

    $argString = "exec --ephemeral -c model_reasoning_effort=low -s read-only -o `"$lastPath`" --cd `"$WorkspacePath`" `"$escapedPrompt`""
    if ($effectiveDisableMcp) {
      $argString = "exec --ephemeral -c model_reasoning_effort=low -c mcp_servers={} -s read-only -o `"$lastPath`" --cd `"$WorkspacePath`" `"$escapedPrompt`""
    }

    $proc = Start-Process `
      -FilePath $codexPath `
      -ArgumentList $argString `
      -NoNewWindow `
      -PassThru `
      -RedirectStandardOutput $attemptStdoutPath `
      -RedirectStandardError $attemptStderrPath

    $attemptTimedOut = $false
    $completed = $proc.WaitForExit($caseTimeoutSeconds * 1000)
    if (-not $completed) {
      $attemptTimedOut = $true
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    $attemptExitCode = if ($attemptTimedOut) { 124 } elseif ($null -eq $proc.ExitCode) { 1 } else { [int]$proc.ExitCode }

    $stdout = ""
    $stderr = ""
    if (Test-Path -LiteralPath $attemptStdoutPath) { $stdout = Get-Content -LiteralPath $attemptStdoutPath -Raw }
    if (Test-Path -LiteralPath $attemptStderrPath) { $stderr = Get-Content -LiteralPath $attemptStderrPath -Raw }

    Append-Utf8NoBomText -Path $stdoutPath -AppendContent ("===== Attempt $attempt =====`r`n$stdout`r`n")
    Append-Utf8NoBomText -Path $stderrPath -AppendContent ("===== Attempt $attempt =====`r`n$stderr`r`n")
    Append-Utf8NoBomText -Path $combinedPath -AppendContent ("===== Attempt $attempt / STDOUT =====`r`n$stdout`r`n===== Attempt $attempt / STDERR =====`r`n$stderr`r`n")

    $lastMessage = ""
    if (Test-Path -LiteralPath $lastPath) {
      $lastMessage = Get-Content -LiteralPath $lastPath -Raw
    }
    if ([string]::IsNullOrWhiteSpace($lastMessage) -and -not [string]::IsNullOrWhiteSpace($stdout)) {
      # Some codex runs may emit final content to stdout while leaving -o output empty.
      # Persist fallback content to keep artifacts and keyword checks stable.
      $lastMessage = $stdout
      Write-Utf8NoBomText -Path $lastPath -Content $lastMessage
    }

    $hits = Get-KeywordHitCount -Text $lastMessage -Keywords $case.keywords
    $hasOutput = -not [string]::IsNullOrWhiteSpace($lastMessage)
    $status = if ($hasOutput -and $hits -ge [int]$case.minHits) { "PASS" } else { "FAIL" }
    $timedOut = $attemptTimedOut
    $exitCode = $attemptExitCode

    if ($status -eq "PASS") {
      break
    }

    $shouldRetry = $false
    if ($attempt -lt $RetryAttempts -and ($attemptTimedOut -or -not $hasOutput)) {
      $shouldRetry = $true
    }
    if ($shouldRetry) {
      Write-Host "Retrying case=$id attempt=$attempt/$RetryAttempts after ${RetryBackoffSeconds}s (exit=$attemptExitCode timed_out=$attemptTimedOut has_output=$hasOutput hits=$hits/$($case.minHits))"
      Start-Sleep -Seconds $RetryBackoffSeconds
    } else {
      break
    }
  }

  $duration = (Get-Date) - $start
  $results.Add([pscustomobject]@{
    id = $id
    timed_out = $timedOut
    exit_code = $exitCode
    keyword_hits = $hits
    keyword_min = [int]$case.minHits
    has_output = $hasOutput
    attempts_used = $attemptsUsed
    duration_seconds = [math]::Round($duration.TotalSeconds, 1)
    status = $status
    output_file = $lastPath
    stdout_file = $stdoutPath
    stderr_file = $stderrPath
    combined_log = $combinedPath
  })
}

$reportPath = Join-Path (Split-Path -Parent $PSScriptRoot) "SMOKE_TEST_RESULTS.md"
$generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

$report = @()
$report += "# SMOKE_TEST_RESULTS"
$report += ""
$report += "- Generated at: $generatedAt"
$report += "- Workspace: $WorkspacePath"
$report += "- Runner: scripts/run_smoke_prompts.ps1"
$report += "- TimeoutSeconds: $TimeoutSeconds"
$report += "- DisableMcp: $DisableMcp"
$report += "- RetryAttempts: $RetryAttempts"
$report += "- RetryBackoffSeconds: $RetryBackoffSeconds"
$report += ""
$report += "| Case | Timeout | Exit Code | Hits/Min | Has Output | Attempts | Status |"
$report += "|---|---|---:|---:|---|---:|---|"

foreach ($r in $results) {
  $report += "| $($r.id) | $($r.timed_out) | $($r.exit_code) | $($r.keyword_hits)/$($r.keyword_min) | $($r.has_output) | $($r.attempts_used) | $($r.status) |"
}

$report += ""
$report += "## Artifacts"
foreach ($r in $results) {
  $report += "- $($r.id): output=$($r.output_file), stdout=$($r.stdout_file), stderr=$($r.stderr_file), combined=$($r.combined_log)"
}

$failed = @($results | Where-Object { $_.status -ne "PASS" })
$report += ""
if ($failed.Count -eq 0) {
  $report += "All selected smoke prompt runs passed."
} else {
  $report += "Failed cases: " + (($failed | Select-Object -ExpandProperty id) -join ", ")
}

Write-Utf8NoBomText -Path $reportPath -Content ($report -join [Environment]::NewLine)

Write-Host ""
Write-Host "Smoke results written to: $reportPath"
if ($failed.Count -gt 0) {
  Write-Host "Failed cases: $($failed.id -join ', ')" -ForegroundColor Yellow
}

if ($FailOnAnyFailure -and $failed.Count -gt 0) {
  exit 1
}

exit 0
