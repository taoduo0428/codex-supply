param(
  [string]$WorkspacePath = "$env:USERPROFILE",
  [switch]$UseSymlink
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$indexPath = Join-Path $scriptDir "index.json"

if (-not (Test-Path -LiteralPath $indexPath)) {
  throw "Missing index.json at $indexPath"
}

$index = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json

$agentsPluginsRoot = Join-Path $env:USERPROFILE ".agents\plugins"
$pluginsRoot = Join-Path $agentsPluginsRoot "plugins"
$marketplacePath = Join-Path $agentsPluginsRoot "marketplace.json"

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $agentsPluginsRoot ("backup-" + $timestamp)
$backupPluginsRoot = Join-Path $backupRoot "plugins"

New-Item -ItemType Directory -Force -Path $pluginsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $agentsPluginsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $backupPluginsRoot | Out-Null

if (Test-Path -LiteralPath $marketplacePath) {
  Copy-Item -LiteralPath $marketplacePath -Destination (Join-Path $backupRoot "marketplace.json") -Force
}

$installed = @()

foreach ($plugin in $index.plugins) {
  $name = [string]$plugin.name
  $src = Join-Path $scriptDir $name
  $dst = Join-Path $pluginsRoot $name
  $backupDst = Join-Path $backupPluginsRoot $name

  if (-not (Test-Path -LiteralPath $src)) {
    throw "Plugin source not found: $src"
  }

  if (Test-Path -LiteralPath $dst) {
    Move-Item -LiteralPath $dst -Destination $backupDst
  }

  if ($UseSymlink) {
    New-Item -ItemType SymbolicLink -Path $dst -Target $src | Out-Null
  }
  else {
    Copy-Item -Recurse -Force -LiteralPath $src -Destination $dst
  }

  if ($name -eq "integration-runtime") {
    $mcpPath = Join-Path $dst ".mcp.json"
    if (Test-Path -LiteralPath $mcpPath) {
      $mcp = Get-Content -LiteralPath $mcpPath -Raw | ConvertFrom-Json
      $mcp.mcpServers.filesystem.args[2] = $WorkspacePath
      $mcp.mcpServers.git.args[1] = $WorkspacePath
      Write-Utf8NoBom -Path $mcpPath -Content ($mcp | ConvertTo-Json -Depth 20)
    }
  }

  $installed += $name
}

if (Test-Path -LiteralPath $marketplacePath) {
  $market = Get-Content -LiteralPath $marketplacePath -Raw | ConvertFrom-Json
}
else {
  $market = [pscustomobject]@{
    name = "local-global"
    interface = [pscustomobject]@{
      displayName = "Local Global Plugins"
    }
    plugins = @()
  }
}

if ($null -eq $market.interface) {
  $market.interface = [pscustomobject]@{ displayName = "Local Global Plugins" }
}
if ($null -eq $market.plugins) {
  $market.plugins = @()
}

$pluginList = @($market.plugins)

foreach ($name in $installed) {
  $marketplaceRelativePath = "./plugins/$name"
  $existing = $pluginList | Where-Object { $_.name -eq $name } | Select-Object -First 1
  if ($null -eq $existing) {
    $entry = [pscustomobject]@{
      name = $name
      source = [pscustomobject]@{
        source = "local"
        path = $marketplaceRelativePath
      }
      policy = [pscustomobject]@{
        installation = "AVAILABLE"
        authentication = "ON_INSTALL"
      }
      category = "Developer Tools"
    }
    $pluginList += $entry
  }
  else {
    if ($null -eq $existing.PSObject.Properties["source"]) {
      $existing | Add-Member -NotePropertyName source -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if ($null -eq $existing.PSObject.Properties["policy"]) {
      $existing | Add-Member -NotePropertyName policy -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    if ($null -eq $existing.source) {
      $existing.source = [pscustomobject]@{}
    }
    if ($null -eq $existing.policy) {
      $existing.policy = [pscustomobject]@{}
    }
    $existing.source.source = "local"
    $existing.source.path = $marketplaceRelativePath
    $existing.policy.installation = "AVAILABLE"
    $existing.policy.authentication = "ON_INSTALL"
    $existing.category = "Developer Tools"
  }
}

$market.plugins = $pluginList
Write-Utf8NoBom -Path $marketplacePath -Content ($market | ConvertTo-Json -Depth 20)

$receipt = [pscustomobject]@{
  installed_at = (Get-Date).ToString("s")
  workspace_path = $WorkspacePath
  backup_root = $backupRoot
  plugins_root = $pluginsRoot
  marketplace_path = $marketplacePath
  installed_plugins = $installed
}

$receiptPath = Join-Path $agentsPluginsRoot "last-global-install.json"
Write-Utf8NoBom -Path $receiptPath -Content ($receipt | ConvertTo-Json -Depth 10)

Write-Host "Global plugins installed."
Write-Host "Plugins root: $pluginsRoot"
Write-Host "Marketplace: $marketplacePath"
Write-Host "Backup: $backupRoot"
Write-Host "Receipt: $receiptPath"
