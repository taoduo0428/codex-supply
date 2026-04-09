param()

$ErrorActionPreference = "Stop"

$tasks = @(
  "Codex-Auto-Daily-Smoke",
  "Codex-Auto-Git-Review"
)

foreach ($name in $tasks) {
  $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
  if ($null -ne $existing) {
    Unregister-ScheduledTask -TaskName $name -Confirm:$false
    Write-Host "Removed: $name"
  } else {
    Write-Host "Not found: $name"
  }
}

Write-Host "Automation cleanup complete."
