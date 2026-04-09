param(
  [string]$ScriptRootPath = "",
  [string]$WorkspacePath = "",
  [string]$GitRepoPath = "",
  [string]$ActiveRepoFilePath = "",
  [string]$DailySmokeTime = "09:00",
  [int]$GitReviewIntervalHours = 4,
  [int]$GitReviewTimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ScriptRootPath)) {
  $ScriptRootPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}
if ([string]::IsNullOrWhiteSpace($WorkspacePath)) {
  $WorkspacePath = $ScriptRootPath
}
if ([string]::IsNullOrWhiteSpace($ActiveRepoFilePath)) {
  $ActiveRepoFilePath = Join-Path $env:USERPROFILE ".agents\active-repo.txt"
}

$ScriptRootPath = [System.IO.Path]::GetFullPath($ScriptRootPath)
$WorkspacePath = [System.IO.Path]::GetFullPath($WorkspacePath)

function Test-GitRepo([string]$PathValue) {
  if ([string]::IsNullOrWhiteSpace($PathValue)) { return $false }
  if (-not (Test-Path -LiteralPath $PathValue)) { return $false }
  return (Test-Path -LiteralPath (Join-Path $PathValue ".git"))
}

if (-not [string]::IsNullOrWhiteSpace($ActiveRepoFilePath)) {
  $activeRepoDir = Split-Path -Path $ActiveRepoFilePath -Parent
  if (-not [string]::IsNullOrWhiteSpace($activeRepoDir)) {
    New-Item -ItemType Directory -Force -Path $activeRepoDir | Out-Null
  }
}

$seedRepoPath = $null
if (Test-GitRepo -PathValue $GitRepoPath) {
  $seedRepoPath = [System.IO.Path]::GetFullPath($GitRepoPath)
}
elseif (Test-GitRepo -PathValue $WorkspacePath) {
  $seedRepoPath = [System.IO.Path]::GetFullPath($WorkspacePath)
}

if (-not [string]::IsNullOrWhiteSpace($seedRepoPath)) {
  Set-Content -LiteralPath $ActiveRepoFilePath -Value $seedRepoPath -Encoding UTF8
}

$dailyScript = Join-Path $ScriptRootPath "scripts\automation_daily_smoke.ps1"
$reviewScript = Join-Path $ScriptRootPath "scripts\automation_git_review.ps1"

if (-not (Test-Path -LiteralPath $dailyScript)) { throw "Missing script: $dailyScript" }
if (-not (Test-Path -LiteralPath $reviewScript)) { throw "Missing script: $reviewScript" }

$taskSmoke = "Codex-Auto-Daily-Smoke"
$taskReview = "Codex-Auto-Git-Review"

$userId = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 4)

$smokeAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$dailyScript`" -ScriptRootPath `"$ScriptRootPath`""
$smokeTrigger = New-ScheduledTaskTrigger -Daily -At $DailySmokeTime

$reviewAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$reviewScript`" -WorkspacePath `"$WorkspacePath`" -ActiveRepoFilePath `"$ActiveRepoFilePath`" -OutputRootPath `"$ScriptRootPath`" -TimeoutSeconds $GitReviewTimeoutSeconds"
$reviewTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours $GitReviewIntervalHours) -RepetitionDuration (New-TimeSpan -Days 3650)

Register-ScheduledTask -TaskName $taskSmoke -Action $smokeAction -Trigger $smokeTrigger -Settings $settings -Principal $principal -Description "Codex global plugin daily smoke automation" -Force | Out-Null
Register-ScheduledTask -TaskName $taskReview -Action $reviewAction -Trigger $reviewTrigger -Settings $settings -Principal $principal -Description "Codex git review automation" -Force | Out-Null

Write-Host "Automations registered."
Write-Host "Task: $taskSmoke (Daily at $DailySmokeTime)"
Write-Host "Task: $taskReview (Every $GitReviewIntervalHours hour(s), starts in ~5 minutes, timeout ${GitReviewTimeoutSeconds}s)"
Write-Host "ScriptRootPath: $ScriptRootPath"
Write-Host "WorkspacePath: $WorkspacePath"
Write-Host "ActiveRepoFilePath: $ActiveRepoFilePath"
if (-not [string]::IsNullOrWhiteSpace($seedRepoPath)) {
  Write-Host "Seeded active repo: $seedRepoPath"
}
else {
  Write-Host "Seeded active repo: (none)"
}
