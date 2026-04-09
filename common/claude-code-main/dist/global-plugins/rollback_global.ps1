param(
  [string]$BackupPath = ""
)

$ErrorActionPreference = "Stop"

$agentsPluginsRoot = Join-Path $env:USERPROFILE ".agents\plugins"
$pluginsRoot = Join-Path $env:USERPROFILE "plugins"
$receiptPath = Join-Path $agentsPluginsRoot "last-global-install.json"

if ([string]::IsNullOrWhiteSpace($BackupPath)) {
  if (-not (Test-Path -LiteralPath $receiptPath)) {
    throw "No receipt found at $receiptPath. Please pass -BackupPath manually."
  }
  $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
  $BackupPath = [string]$receipt.backup_root
}

if (-not (Test-Path -LiteralPath $BackupPath)) {
  throw "Backup path not found: $BackupPath"
}

$rollbackTs = Get-Date -Format "yyyyMMdd-HHmmss"
$safetyRoot = Join-Path $agentsPluginsRoot ("rollback-safety-" + $rollbackTs)
$safetyPlugins = Join-Path $safetyRoot "plugins"

New-Item -ItemType Directory -Force -Path $safetyPlugins | Out-Null

$backupPlugins = Join-Path $BackupPath "plugins"
if (Test-Path -LiteralPath $backupPlugins) {
  Get-ChildItem -LiteralPath $backupPlugins -Directory | ForEach-Object {
    $name = $_.Name
    $dst = Join-Path $pluginsRoot $name
    $safetyDst = Join-Path $safetyPlugins $name
    if (Test-Path -LiteralPath $dst) {
      Move-Item -LiteralPath $dst -Destination $safetyDst
    }
    Move-Item -LiteralPath $_.FullName -Destination $dst
  }
}

$backupMarket = Join-Path $BackupPath "marketplace.json"
$marketPath = Join-Path $agentsPluginsRoot "marketplace.json"
if (Test-Path -LiteralPath $backupMarket) {
  if (Test-Path -LiteralPath $marketPath) {
    Copy-Item -LiteralPath $marketPath -Destination (Join-Path $safetyRoot "marketplace.json") -Force
  }
  Copy-Item -LiteralPath $backupMarket -Destination $marketPath -Force
}

Write-Host "Rollback complete."
Write-Host "Restored from: $BackupPath"
Write-Host "Safety backup of replaced current state: $safetyRoot"
