param(
  [Alias("RepoPath")]
  [string]$WorkspacePath = "",
  [string]$ActiveRepoFilePath = "",
  [string]$OutputRootPath = "",
  [int]$TimeoutSeconds = 420
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($WorkspacePath)) {
  if (-not [string]::IsNullOrWhiteSpace($env:CODEX_WORKSPACE_PATH)) {
    $WorkspacePath = $env:CODEX_WORKSPACE_PATH
  }
  elseif (-not [string]::IsNullOrWhiteSpace($env:CODEX_WORKSPACE)) {
    $WorkspacePath = $env:CODEX_WORKSPACE
  }
  else {
    $WorkspacePath = (Get-Location).Path
  }
}

if ([string]::IsNullOrWhiteSpace($ActiveRepoFilePath)) {
  $ActiveRepoFilePath = Join-Path $env:USERPROFILE ".agents\active-repo.txt"
}

if ([string]::IsNullOrWhiteSpace($OutputRootPath)) {
  $OutputRootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

$WorkspacePath = [System.IO.Path]::GetFullPath($WorkspacePath)
$OutputRootPath = [System.IO.Path]::GetFullPath($OutputRootPath)

function Get-AutomationBasePath([string]$RootPath) {
  $leaf = Split-Path -Path $RootPath -Leaf
  if ($leaf -ieq "automation") {
    return $RootPath
  }
  return (Join-Path $RootPath "automation")
}

$automationBasePath = Get-AutomationBasePath -RootPath $OutputRootPath
$logsDir = Join-Path $automationBasePath "logs"
$reportsDir = Join-Path $automationBasePath "reports"
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stdoutPath = Join-Path $logsDir ("git-review-" + $timestamp + ".stdout.log")
$stderrPath = Join-Path $logsDir ("git-review-" + $timestamp + ".stderr.log")
$reportPath = Join-Path $reportsDir ("git-review-" + $timestamp + ".md")
$latestReportPath = Join-Path $reportsDir "git-review-latest.md"
$metaPath = Join-Path $reportsDir ("git-review-" + $timestamp + ".meta.txt")
$script:RepoPath = ""

function Write-Meta([string]$Message) {
  $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
  Add-Content -LiteralPath $metaPath -Value $line
}

function Test-GitRepo([string]$PathValue) {
  if ([string]::IsNullOrWhiteSpace($PathValue)) { return $false }
  if (-not (Test-Path -LiteralPath $PathValue)) { return $false }
  return (Test-Path -LiteralPath (Join-Path $PathValue ".git"))
}

function Resolve-TargetRepoPath {
  if (Test-GitRepo -PathValue $WorkspacePath) {
    return [System.IO.Path]::GetFullPath($WorkspacePath)
  }

  if (Test-Path -LiteralPath $ActiveRepoFilePath) {
    try {
      $first = Get-Content -LiteralPath $ActiveRepoFilePath -ErrorAction Stop | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
      if (-not [string]::IsNullOrWhiteSpace($first)) {
        $candidate = $first.Trim()
        if (Test-GitRepo -PathValue $candidate) {
          return [System.IO.Path]::GetFullPath($candidate)
        }
      }
    }
    catch {}
  }

  return $null
}

function Get-GitOutput([string[]]$Arguments) {
  try {
    $output = & git -C $script:RepoPath @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    if ($null -eq $output) { return @() }
    if ($output -is [System.Array]) { return $output }
    return @([string]$output)
  }
  catch {
    return @()
  }
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

function Write-FallbackReport([string]$Reason) {
  $generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $branch = (Get-GitOutput @("rev-parse", "--abbrev-ref", "HEAD") | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($branch)) { $branch = "(unknown)" }

  $statusLines = Get-GitOutput @("status", "--short")
  $stagedFiles = Get-GitOutput @("diff", "--cached", "--name-only")
  $unstagedFiles = Get-GitOutput @("diff", "--name-only")
  $recentCommits = Get-GitOutput @("log", "-5", "--pretty=format:- %h %s (%cr)")

  $stagedCount = if ($stagedFiles) { ($stagedFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count } else { 0 }
  $unstagedCount = if ($unstagedFiles) { ($unstagedFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count } else { 0 }
  $totalChanged = if ($statusLines) { ($statusLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count } else { 0 }

  $riskHints = New-Object System.Collections.Generic.List[string]
  if ($totalChanged -gt 20) { [void]$riskHints.Add("Many files changed; split commits to reduce review risk.") }
  if ($stagedCount -eq 0 -and $unstagedCount -gt 0) { [void]$riskHints.Add("No staged changes yet; stage by feature before commit.") }
  if ($stagedCount -gt 0 -and $unstagedCount -gt 0) { [void]$riskHints.Add("Mixed staged/unstaged state; verify commit boundary.") }
  if ($totalChanged -eq 0) { [void]$riskHints.Add("No uncommitted changes; focus on latest commit quality.") }
  if ($riskHints.Count -eq 0) { [void]$riskHints.Add("No high-risk signal detected from git state.") }

  $commitPlan = @(
    "1. Split changes into small, reversible commits.",
    "2. Run minimum checks (tests/lint/type-check) before commit.",
    "3. Use clear commit message format: <type>(scope): summary.",
    "4. Add short impact notes for reviewer context."
  )

  $checklist = @(
    "- [ ] Local checks passed (minimum critical path)",
    "- [ ] No temporary debug code/logs left",
    "- [ ] Commit message is clear and scoped",
    "- [ ] Docs/examples updated when config changed"
  )

  $lines = New-Object System.Collections.Generic.List[string]
  [void]$lines.Add("# Git Review Report (Fallback)")
  [void]$lines.Add("")
  [void]$lines.Add("- Generated: $generatedAt")
  [void]$lines.Add("- Repo: $script:RepoPath")
  [void]$lines.Add("- Branch: $branch")
  [void]$lines.Add("- Reason: $Reason")
  [void]$lines.Add("")
  [void]$lines.Add("## Summary")
  [void]$lines.Add("- Changed entries: $totalChanged")
  [void]$lines.Add("- Staged files: $stagedCount")
  [void]$lines.Add("- Unstaged files: $unstagedCount")
  [void]$lines.Add("")
  [void]$lines.Add("## Top Risks")
  foreach ($risk in $riskHints) { [void]$lines.Add("- $risk") }
  [void]$lines.Add("")
  [void]$lines.Add("## Commit Plan")
  foreach ($step in $commitPlan) { [void]$lines.Add("- $step") }
  [void]$lines.Add("")
  [void]$lines.Add("## Commit Quality Checklist")
  foreach ($item in $checklist) { [void]$lines.Add($item) }
  [void]$lines.Add("")
  [void]$lines.Add("## Recent Commits")
  if ($recentCommits -and $recentCommits.Count -gt 0) {
    foreach ($commit in $recentCommits) { [void]$lines.Add($commit) }
  }
  else {
    [void]$lines.Add("- (no commits found)")
  }
  [void]$lines.Add("")
  [void]$lines.Add("## Changed Files (status --short)")
  if ($statusLines -and $statusLines.Count -gt 0) {
    [void]$lines.Add('```text')
    foreach ($line in $statusLines) { [void]$lines.Add($line) }
    [void]$lines.Add('```')
  }
  else {
    [void]$lines.Add("- (clean working tree)")
  }

  $content = ($lines -join [Environment]::NewLine)
  Set-Content -LiteralPath $reportPath -Value $content -Encoding UTF8
}

Write-Meta "Automation git review started."
Write-Meta "WorkspacePath: $WorkspacePath"
Write-Meta "ActiveRepoFilePath: $ActiveRepoFilePath"
Write-Meta "OutputRootPath: $OutputRootPath"

$targetRepo = Resolve-TargetRepoPath
if ([string]::IsNullOrWhiteSpace($targetRepo)) {
  Write-Meta "Skipped: no valid git repo from workspace or active-repo fallback."
  exit 0
}
$script:RepoPath = $targetRepo
Write-Meta "Resolved target repo: $script:RepoPath"

$statusShort = Get-GitOutput @("status", "--short")
$hasWorktreeChanges = ($statusShort -and (($statusShort | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0))
$lastCommit = (Get-GitOutput @("log", "-1", "--pretty=format:%h %s (%cr)") | Select-Object -First 1)

if (-not $hasWorktreeChanges -and [string]::IsNullOrWhiteSpace($lastCommit)) {
  Write-Meta "No git information available."
  exit 0
}

$prompt = @"
Review this repository state and produce a concise git review report:
- summarize current changes and/or latest commit context
- identify top risks or regressions
- propose a clean commit plan
- include a short checklist for next commit quality
Do not modify any files.
"@

$escapedPrompt = $prompt.Replace('"', '\"')
$argString = "exec -c model_reasoning_effort=low -s read-only -o `"$reportPath`" --cd `"$script:RepoPath`" `"$escapedPrompt`""

$timedOut = $false
$codexStarted = $false
$exitCode = 1
$codexPath = Resolve-CodexPath
if ([string]::IsNullOrWhiteSpace($codexPath)) {
  Write-Meta "Codex binary not found in PATH or known extension paths."
}
else {
  Write-Meta "Codex binary resolved: $codexPath"
}

try {
  if ([string]::IsNullOrWhiteSpace($codexPath)) {
    throw "codex executable is not available"
  }
  Write-Meta "Starting codex exec for git review."
  $proc = Start-Process `
    -FilePath $codexPath `
    -ArgumentList $argString `
    -NoNewWindow `
    -PassThru `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath
  $codexStarted = $true
}
catch {
  Write-Meta "Failed to start codex process: $($_.Exception.Message)"
}

if ($codexStarted) {
  $completed = $proc.WaitForExit($TimeoutSeconds * 1000)
  if (-not $completed) {
    $timedOut = $true
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    $exitCode = 124
  }
  elseif ($null -eq $proc.ExitCode) {
    $exitCode = 1
  }
  else {
    $exitCode = [int]$proc.ExitCode
  }
}
else {
  $exitCode = 127
}

Write-Meta "codex exit code: $exitCode"
Write-Meta "timed out: $timedOut"

$hasReport = (Test-Path -LiteralPath $reportPath) -and ((Get-Item -LiteralPath $reportPath).Length -gt 0)
if (-not $hasReport) {
  $fallbackReason = if ($timedOut) { "codex exec timed out" } elseif ($exitCode -eq 127) { "codex process unavailable" } else { "codex exec failed to generate report" }
  Write-Meta "No report from codex. Fallback reason: $fallbackReason"
  Write-FallbackReport -Reason $fallbackReason
  $hasReport = (Test-Path -LiteralPath $reportPath) -and ((Get-Item -LiteralPath $reportPath).Length -gt 0)
  if ($hasReport) {
    Write-Meta "Fallback report generated."
  }
}

if (-not $hasReport) {
  Write-Meta "Final status: failed (no report)."
  exit 1
}

Copy-Item -LiteralPath $reportPath -Destination $latestReportPath -Force
Write-Meta "Report generated: $reportPath"
Write-Meta "Latest report: $latestReportPath"
Write-Meta "Final status: success."

exit 0
