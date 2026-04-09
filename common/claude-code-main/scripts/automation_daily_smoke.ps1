param(
  [Alias("RepoPath")]
  [string]$ScriptRootPath = "",
  [int]$SmokeTimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ScriptRootPath)) {
  $ScriptRootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

function Get-AutomationBasePath([string]$RootPath) {
  $leaf = Split-Path -Path $RootPath -Leaf
  if ($leaf -ieq "automation") {
    return $RootPath
  }
  return (Join-Path $RootPath "automation")
}

$automationBasePath = Get-AutomationBasePath -RootPath $ScriptRootPath
$logsDir = Join-Path $automationBasePath "logs"
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $logsDir ("daily-smoke-" + $timestamp + ".log")

function Write-Log([string]$Message) {
  $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
  Write-Host $line
  Add-Content -LiteralPath $logPath -Value $line
}

function Get-InstallWorkspacePath {
  $receiptPath = Join-Path $env:USERPROFILE ".agents\plugins\last-global-install.json"
  if (-not (Test-Path -LiteralPath $receiptPath)) {
    return $null
  }
  try {
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    return [string]$receipt.workspace_path
  }
  catch {
    return $null
  }
}

Write-Log "Automation daily smoke started."
Write-Log "ScriptRootPath: $ScriptRootPath"

$workspacePath = Get-InstallWorkspacePath
if ([string]::IsNullOrWhiteSpace($workspacePath)) {
  $workspacePath = $ScriptRootPath
}
Write-Log "WorkspacePath used for runtime validation: $workspacePath"

$validateScript = Join-Path $ScriptRootPath "scripts\validate_global_runtime.ps1"
$smokeScript = Join-Path $ScriptRootPath "scripts\run_smoke_prompts.ps1"

if (-not (Test-Path -LiteralPath $validateScript)) {
  Write-Log "Missing script: $validateScript"
  exit 1
}
if (-not (Test-Path -LiteralPath $smokeScript)) {
  Write-Log "Missing script: $smokeScript"
  exit 1
}

Write-Log "Step 1/2: validate global runtime"
& powershell -NoProfile -ExecutionPolicy Bypass -File $validateScript -ExpectedWorkspacePath $workspacePath -StrictGithubToken 2>&1 | ForEach-Object {
  Add-Content -LiteralPath $logPath -Value $_
}
$validateExit = $LASTEXITCODE
Write-Log "validate_global_runtime exit code: $validateExit"
if ($validateExit -ne 0) {
  Write-Log "Automation failed at runtime validation."
  exit $validateExit
}

Write-Log "Step 2/2: run smoke prompts"
& powershell -NoProfile -ExecutionPolicy Bypass -File $smokeScript -WorkspacePath $workspacePath -TimeoutSeconds $SmokeTimeoutSeconds -FailOnAnyFailure 2>&1 | ForEach-Object {
  Add-Content -LiteralPath $logPath -Value $_
}
$smokeExit = $LASTEXITCODE
Write-Log "run_smoke_prompts exit code: $smokeExit"

if ($smokeExit -ne 0) {
  Write-Log "Automation finished with failures."
  exit $smokeExit
}

Write-Log "Automation daily smoke finished successfully."
exit 0
