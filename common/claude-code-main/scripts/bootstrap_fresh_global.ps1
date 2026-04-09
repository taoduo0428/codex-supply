param(
  [Parameter(Mandatory = $true)][string]$RepoRoot,
  [Parameter(Mandatory = $true)][string]$WorkspacePath,
  [string]$SkillsSourcePath = "",
  [string]$DailySmokeTime = "09:00",
  [int]$GitReviewIntervalHours = 4,
  [int]$GitReviewTimeoutSeconds = 120,
  [switch]$EnableGitReview,
  [switch]$UseSymlink,
  [string]$GithubToken = ""
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
  Write-Host "[STEP] $Message" -ForegroundColor Cyan
}

function Write-Info([string]$Message) {
  Write-Host "[INFO] $Message" -ForegroundColor Gray
}

function Write-Ok([string]$Message) {
  Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
  Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Resolve-FullPath([string]$PathValue) {
  if ([string]::IsNullOrWhiteSpace($PathValue)) { return "" }
  return [System.IO.Path]::GetFullPath($PathValue)
}

function Write-IntegrationMcpConfig(
  [string]$McpPath,
  [string]$Workspace,
  [string]$FetchCommand,
  [string]$GitCommand
) {
  $mcp = [ordered]@{
    mcpServers = [ordered]@{
      playwright = [ordered]@{
        command = "npx"
        args = @("-y", "@playwright/mcp@latest")
      }
      filesystem = [ordered]@{
        command = "npx"
        args = @("-y", "@modelcontextprotocol/server-filesystem", $Workspace)
      }
      fetch = [ordered]@{
        command = $FetchCommand
        args = @()
      }
      git = [ordered]@{
        command = $GitCommand
        args = @("--repository", $Workspace)
      }
      github = [ordered]@{
        command = "npx"
        args = @("-y", "@modelcontextprotocol/server-github")
        env = [ordered]@{
          GITHUB_PERSONAL_ACCESS_TOKEN = '${GITHUB_TOKEN}'
        }
      }
      openaiDeveloperDocs = [ordered]@{
        url = "https://developers.openai.com/mcp"
      }
    }
  }
  $mcp | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $McpPath -Encoding UTF8
}

$RepoRoot = Resolve-FullPath $RepoRoot
$WorkspacePath = Resolve-FullPath $WorkspacePath
if (-not [string]::IsNullOrWhiteSpace($SkillsSourcePath)) {
  $SkillsSourcePath = Resolve-FullPath $SkillsSourcePath
}

if (-not (Test-Path -LiteralPath $RepoRoot)) {
  throw "RepoRoot not found: $RepoRoot"
}
if (-not (Test-Path -LiteralPath $WorkspacePath)) {
  throw "WorkspacePath not found: $WorkspacePath"
}

$installScript = Join-Path $RepoRoot "dist\global-plugins\install_global.ps1"
$sourceScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $installScript)) {
  throw "Missing installer: $installScript"
}
if (-not (Test-Path -LiteralPath $sourceScriptsDir)) {
  throw "Missing scripts dir: $sourceScriptsDir"
}

$globalPluginsRoot = Join-Path $env:USERPROFILE ".agents\plugins"
$globalPluginsDir = Join-Path $globalPluginsRoot "plugins"
$globalAutomationRoot = Join-Path $env:USERPROFILE ".agents\automation"
$globalAutomationScripts = Join-Path $globalAutomationRoot "scripts"
$globalSkillsDir = Join-Path $env:USERPROFILE ".agents\skills"
$activeRepoFilePath = Join-Path $env:USERPROFILE ".agents\active-repo.txt"
$fetchCommand = "mcp-server-fetch"
$gitCommand = "mcp-server-git"

Write-Step "Preflight checks"
foreach ($cmd in @("git", "npx")) {
  if ($null -eq (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Write-Warn "Command not found: $cmd (some MCP/plugin features may not work)."
  } else {
    Write-Ok "Command found: $cmd"
  }
}
if ($null -eq (Get-Command py -ErrorAction SilentlyContinue)) {
  Write-Warn "Python launcher 'py' not found. Skipping python MCP package install."
} else {
  Write-Ok "Python launcher found: py"
}

if (-not [string]::IsNullOrWhiteSpace($GithubToken)) {
  Write-Step "Setting user-level GITHUB_TOKEN"
  [Environment]::SetEnvironmentVariable("GITHUB_TOKEN", $GithubToken, "User")
  Write-Ok "GITHUB_TOKEN set."
}

Write-Step "Installing global plugins"
$installArgs = @(
  "-ExecutionPolicy", "Bypass",
  "-File", $installScript,
  "-WorkspacePath", $WorkspacePath
)
if ($UseSymlink) {
  $installArgs += "-UseSymlink"
}
& powershell @installArgs
if ($LASTEXITCODE -ne 0) {
  throw "Global plugin install failed, exit code=$LASTEXITCODE"
}
Write-Ok "Global plugins installed."

Write-Step "Copying automation scripts to global runtime"
New-Item -ItemType Directory -Force -Path $globalAutomationScripts | Out-Null
$scriptFiles = @(
  "automation_daily_smoke.ps1",
  "automation_git_review.ps1",
  "setup_automations.ps1",
  "remove_automations.ps1",
  "set_active_repo.ps1",
  "validate_global_runtime.ps1",
  "run_smoke_prompts.ps1"
)
foreach ($name in $scriptFiles) {
  $src = Join-Path $sourceScriptsDir $name
  if (-not (Test-Path -LiteralPath $src)) {
    throw "Missing required script: $src"
  }
  Copy-Item -LiteralPath $src -Destination (Join-Path $globalAutomationScripts $name) -Force
}
Write-Ok "Automation scripts copied: $globalAutomationScripts"

Write-Step "Syncing integration-runtime MCP workspace paths"
$integrationMcpPath = Join-Path $globalPluginsDir "integration-runtime\.mcp.json"
if (Test-Path -LiteralPath $integrationMcpPath) {
  Write-IntegrationMcpConfig -McpPath $integrationMcpPath -Workspace $WorkspacePath -FetchCommand $fetchCommand -GitCommand $gitCommand
  Write-Ok "MCP workspace paths synced to: $WorkspacePath"
}
else {
  Write-Warn "integration-runtime .mcp.json not found: $integrationMcpPath"
}

Write-Step "Installing python MCP dependencies (fetch/git)"
if ($null -ne (Get-Command py -ErrorAction SilentlyContinue)) {
  & py -m pip install --user --disable-pip-version-check mcp-server-fetch mcp-server-git
  if ($LASTEXITCODE -eq 0) {
    Write-Ok "Python MCP dependencies installed."
    $pyScriptsPath = (& py -c "import sysconfig; print(sysconfig.get_path('scripts', 'nt_user'))" 2>$null | Select-Object -First 1)
    if (-not [string]::IsNullOrWhiteSpace($pyScriptsPath)) {
      $fetchExe = Join-Path $pyScriptsPath "mcp-server-fetch.exe"
      $gitExe = Join-Path $pyScriptsPath "mcp-server-git.exe"
      if (Test-Path -LiteralPath $fetchExe) {
        $fetchCommand = $fetchExe
      }
      if (Test-Path -LiteralPath $gitExe) {
        $gitCommand = $gitExe
      }
      Write-Info "Resolved fetch command: $fetchCommand"
      Write-Info "Resolved git command: $gitCommand"
    }
    if (Test-Path -LiteralPath $integrationMcpPath) {
      Write-IntegrationMcpConfig -McpPath $integrationMcpPath -Workspace $WorkspacePath -FetchCommand $fetchCommand -GitCommand $gitCommand
      Write-Ok "MCP command paths refreshed after python install."
    }
  }
  else {
    Write-Warn "Python MCP dependency install returned exit code $LASTEXITCODE."
  }
}

if (-not [string]::IsNullOrWhiteSpace($SkillsSourcePath)) {
  Write-Step "Syncing skills to user-level directory"
  if (-not (Test-Path -LiteralPath $SkillsSourcePath)) {
    throw "SkillsSourcePath not found: $SkillsSourcePath"
  }
  New-Item -ItemType Directory -Force -Path $globalSkillsDir | Out-Null
  Get-ChildItem -Path $SkillsSourcePath -Force | ForEach-Object {
    $dst = Join-Path $globalSkillsDir $_.Name
    Copy-Item -LiteralPath $_.FullName -Destination $dst -Recurse -Force
  }
  Write-Ok "Skills synced: $SkillsSourcePath -> $globalSkillsDir"
}
else {
  Write-Info "SkillsSourcePath not provided; skipping skill sync."
}

Write-Step "Registering scheduled tasks"
$globalSetupScript = Join-Path $globalAutomationScripts "setup_automations.ps1"
& powershell -ExecutionPolicy Bypass -File $globalSetupScript `
  -ScriptRootPath $globalAutomationRoot `
  -WorkspacePath $WorkspacePath `
  -GitRepoPath $WorkspacePath `
  -ActiveRepoFilePath $activeRepoFilePath `
  -DailySmokeTime $DailySmokeTime `
  -GitReviewIntervalHours $GitReviewIntervalHours `
  -GitReviewTimeoutSeconds $GitReviewTimeoutSeconds
if ($LASTEXITCODE -ne 0) {
  throw "setup_automations failed, exit code=$LASTEXITCODE"
}
Write-Ok "Scheduled tasks registered."

if (-not $EnableGitReview) {
  Write-Step "Disabling Git-Review task (requested)"
  $gitTask = Get-ScheduledTask -TaskName "Codex-Auto-Git-Review" -ErrorAction SilentlyContinue
  if ($null -ne $gitTask) {
    Unregister-ScheduledTask -TaskName "Codex-Auto-Git-Review" -Confirm:$false
    Write-Ok "Removed task: Codex-Auto-Git-Review"
  }
}

if (Test-Path -LiteralPath (Join-Path $WorkspacePath ".git")) {
  Write-Step "Setting active repo pointer"
  $setActiveScript = Join-Path $globalAutomationScripts "set_active_repo.ps1"
  & powershell -ExecutionPolicy Bypass -File $setActiveScript -RepoPath $WorkspacePath -ActiveRepoFilePath $activeRepoFilePath
  if ($LASTEXITCODE -ne 0) {
    Write-Warn "set_active_repo returned exit code $LASTEXITCODE"
  }
}
else {
  Write-Info "Workspace is not a git repo; active-repo pointer not set."
}

Write-Step "Final verification"
if (Test-Path -LiteralPath $globalPluginsDir) {
  Write-Host "Global plugins:"
  Get-ChildItem -Path $globalPluginsDir -Directory | Select-Object -ExpandProperty Name | ForEach-Object { " - $_" }
}
Get-ScheduledTask -TaskName "Codex-Auto-Daily-Smoke" -ErrorAction SilentlyContinue | Select-Object TaskName, State | Format-Table -AutoSize
Get-ScheduledTask -TaskName "Codex-Auto-Git-Review" -ErrorAction SilentlyContinue | Select-Object TaskName, State | Format-Table -AutoSize
if (Test-Path -LiteralPath $activeRepoFilePath) {
  Write-Host "Active repo:"
  Get-Content -LiteralPath $activeRepoFilePath
}

Write-Ok "Bootstrap completed."
