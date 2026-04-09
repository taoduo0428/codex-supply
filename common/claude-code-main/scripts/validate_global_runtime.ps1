param(
  [string]$ExpectedWorkspacePath = "",
  [switch]$StrictGithubToken
)

$ErrorActionPreference = "Stop"

$issues = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$mcp = $null

function Write-Pass([string]$Message) {
  Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-Fail([string]$Message) {
  Write-Host "[FAIL] $Message" -ForegroundColor Red
  $script:issues.Add($Message)
}

function Write-Warn([string]$Message) {
  Write-Host "[WARN] $Message" -ForegroundColor Yellow
  $script:warnings.Add($Message)
}

function Test-CommandResolvable([string]$CommandValue) {
  if ([string]::IsNullOrWhiteSpace($CommandValue)) {
    return $false
  }
  if (Test-Path -LiteralPath $CommandValue) {
    return $true
  }
  try {
    $null = Get-Command $CommandValue -ErrorAction Stop
    return $true
  } catch {
    return $false
  }
}

$expectedPlugins = @(
  "workspace-core",
  "git-review",
  "agent-orchestration",
  "integration-runtime",
  "personal-productivity"
)

$marketplacePath = Join-Path $env:USERPROFILE ".agents\plugins\marketplace.json"
$pluginsRoot = Join-Path $env:USERPROFILE ".agents\plugins\plugins"
$integrationMcpPath = Join-Path $pluginsRoot "integration-runtime\.mcp.json"
$lastInstallPath = Join-Path $env:USERPROFILE ".agents\plugins\last-global-install.json"

if ([string]::IsNullOrWhiteSpace($ExpectedWorkspacePath) -and (Test-Path -LiteralPath $lastInstallPath)) {
  try {
    $installReceipt = Get-Content -LiteralPath $lastInstallPath -Raw | ConvertFrom-Json
    $inferred = [string]$installReceipt.workspace_path
    if (-not [string]::IsNullOrWhiteSpace($inferred)) {
      $ExpectedWorkspacePath = $inferred
      Write-Pass "Inferred expected workspace path from install receipt: $ExpectedWorkspacePath"
    }
  } catch {
    Write-Warn "Failed to parse install receipt for workspace inference: $lastInstallPath"
  }
}

Write-Host "Checking global plugin directories..."
foreach ($name in $expectedPlugins) {
  $path = Join-Path $pluginsRoot $name
  if (Test-Path -LiteralPath $path) {
    Write-Pass "Plugin directory exists: $path"
  } else {
    Write-Fail "Plugin directory missing: $path"
  }
}

Write-Host ""
Write-Host "Checking global marketplace registry..."
if (-not (Test-Path -LiteralPath $marketplacePath)) {
  Write-Fail "Marketplace file missing: $marketplacePath"
} else {
  Write-Pass "Marketplace file exists: $marketplacePath"
  try {
    $market = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
  } catch {
    Write-Fail "Marketplace JSON parse failed: $marketplacePath"
    $market = $null
  }

  if ($null -ne $market) {
    $marketplaceDir = Split-Path -Parent $marketplacePath
    foreach ($name in $expectedPlugins) {
      $entry = @($market.plugins | Where-Object { $_.name -eq $name }) | Select-Object -First 1
      if ($null -eq $entry) {
        Write-Fail "Marketplace entry missing: $name"
        continue
      }

      $registeredPath = [string]$entry.source.path
      if ([string]::IsNullOrWhiteSpace($registeredPath)) {
        Write-Fail "Marketplace entry has empty path: $name"
      } else {
        Write-Pass "Marketplace entry found: $name -> $registeredPath"
        $resolvedPath = $registeredPath
        if (-not [System.IO.Path]::IsPathRooted($registeredPath)) {
          $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $marketplaceDir $registeredPath))
        }
        if (Test-Path -LiteralPath $resolvedPath) {
          Write-Pass "Registered path exists: $resolvedPath"
        } else {
          Write-Fail "Registered path missing on disk: $resolvedPath"
        }
      }
    }
  }
}

Write-Host ""
Write-Host "Checking integration-runtime MCP wiring..."
if (-not (Test-Path -LiteralPath $integrationMcpPath)) {
  Write-Fail "integration-runtime MCP file missing: $integrationMcpPath"
} else {
  Write-Pass "integration-runtime MCP file exists: $integrationMcpPath"

  try {
    $mcp = Get-Content -LiteralPath $integrationMcpPath -Raw | ConvertFrom-Json
  } catch {
    Write-Fail "integration-runtime MCP JSON parse failed: $integrationMcpPath"
    $mcp = $null
  }

  if ($null -ne $mcp) {
    $requiredServers = @(
      "playwright",
      "filesystem",
      "fetch",
      "git",
      "github",
      "openaiDeveloperDocs"
    )

    foreach ($server in $requiredServers) {
      if ($null -ne $mcp.mcpServers.$server) {
        Write-Pass "MCP server exists: $server"
      } else {
        Write-Fail "MCP server missing: $server"
      }
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedWorkspacePath)) {
      $fsPath = [string]$mcp.mcpServers.filesystem.args[2]
      $gitPath = [string]$mcp.mcpServers.git.args[1]

      if ($fsPath -eq $ExpectedWorkspacePath) {
        Write-Pass "filesystem workspace path matches expected value"
      } else {
        Write-Fail "filesystem workspace path mismatch. expected='$ExpectedWorkspacePath' actual='$fsPath'"
      }

      if ($gitPath -eq $ExpectedWorkspacePath) {
        Write-Pass "git workspace path matches expected value"
      } else {
        Write-Fail "git workspace path mismatch. expected='$ExpectedWorkspacePath' actual='$gitPath'"
      }
    } else {
      Write-Warn "ExpectedWorkspacePath not provided, skipped workspace path equality checks."
    }
  }
}

Write-Host ""
Write-Host "Checking workspace git topology..."
if (-not [string]::IsNullOrWhiteSpace($ExpectedWorkspacePath)) {
  $workspaceGitPath = Join-Path $ExpectedWorkspacePath ".git"
  if (Test-Path -LiteralPath $workspaceGitPath) {
    try {
      $workspaceTop = (& git -C $ExpectedWorkspacePath rev-parse --show-toplevel 2>$null | Select-Object -First 1)
      if ([string]::IsNullOrWhiteSpace($workspaceTop)) {
        Write-Warn "Unable to resolve git top-level for expected workspace: $ExpectedWorkspacePath"
      } elseif ($workspaceTop -eq $ExpectedWorkspacePath) {
        Write-Pass "Workspace is an independent git repository: $ExpectedWorkspacePath"
      } else {
        Write-Warn "Workspace is nested in a parent git repository. workspace='$ExpectedWorkspacePath' repo_top='$workspaceTop'"
      }
    } catch {
      Write-Warn "Failed to inspect git topology for workspace: $ExpectedWorkspacePath"
    }
  } else {
    Write-Warn "Expected workspace is not initialized as a git repository: $ExpectedWorkspacePath"
  }
} else {
  Write-Warn "ExpectedWorkspacePath not provided, skipped git topology check."
}

Write-Host ""
Write-Host "Checking executable paths..."
$codexCmd = Get-Command codex -ErrorAction SilentlyContinue
if ($null -eq $codexCmd) {
  Write-Fail "codex executable not found in PATH."
} else {
  try {
    & $codexCmd.Source --version *> $null
    if ($LASTEXITCODE -eq 0) {
      Write-Pass "codex executable is runnable: $($codexCmd.Source)"
    } else {
      Write-Fail "codex executable exists but '--version' exited with code ${LASTEXITCODE}: $($codexCmd.Source)"
    }
  } catch {
    Write-Fail "codex executable exists but '--version' failed: $($codexCmd.Source)"
  }
}

if ($null -ne $mcp) {
  $fetchCmd = [string]$mcp.mcpServers.fetch.command
  $gitCmd = [string]$mcp.mcpServers.git.command
  if (Test-CommandResolvable $fetchCmd) {
    Write-Pass "Fetch executable is resolvable: $fetchCmd"
  } else {
    Write-Fail "Fetch executable is not resolvable: $fetchCmd"
  }
  if (Test-CommandResolvable $gitCmd) {
    Write-Pass "Git executable is resolvable: $gitCmd"
  } else {
    Write-Fail "Git executable is not resolvable: $gitCmd"
  }
}

Write-Host ""
Write-Host "Checking GitHub token for GitHub MCP..."
$githubToken = if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
  $env:GITHUB_TOKEN
} elseif (-not [string]::IsNullOrWhiteSpace($env:GITHUB_PAT)) {
  $env:GITHUB_PAT
} else {
  $userToken = [Environment]::GetEnvironmentVariable("GITHUB_TOKEN", "User")
  if (-not [string]::IsNullOrWhiteSpace($userToken)) {
    $userToken
  } else {
    [Environment]::GetEnvironmentVariable("GITHUB_PAT", "User")
  }
}

if ([string]::IsNullOrWhiteSpace($githubToken)) {
  if ($StrictGithubToken) {
    Write-Fail "GITHUB_TOKEN/GITHUB_PAT is not set (process/User scope)."
  } else {
    Write-Warn "GITHUB_TOKEN/GITHUB_PAT is not set (process/User scope). GitHub MCP may fail authentication."
  }
} else {
  Write-Pass "GitHub token is available (process/User scope)."
}

Write-Host ""
if ($issues.Count -gt 0) {
  Write-Host "Validation failed with $($issues.Count) issue(s)." -ForegroundColor Red
  foreach ($issue in $issues) {
    Write-Host " - $issue" -ForegroundColor Red
  }
  exit 1
}

if ($warnings.Count -gt 0) {
  Write-Host "Validation passed with $($warnings.Count) warning(s)." -ForegroundColor Yellow
  foreach ($warning in $warnings) {
    Write-Host " - $warning" -ForegroundColor Yellow
  }
}

Write-Host "All required global runtime checks passed." -ForegroundColor Green
exit 0
