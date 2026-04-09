param(
  [string]$RepoPath = "",
  [string]$ActiveRepoFilePath = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoPath)) {
  $RepoPath = (Get-Location).Path
}
if ([string]::IsNullOrWhiteSpace($ActiveRepoFilePath)) {
  $ActiveRepoFilePath = Join-Path $env:USERPROFILE ".agents\active-repo.txt"
}

$RepoPath = [System.IO.Path]::GetFullPath($RepoPath)

if (-not (Test-Path -LiteralPath $RepoPath)) {
  throw "RepoPath not found: $RepoPath"
}
if (-not (Test-Path -LiteralPath (Join-Path $RepoPath ".git"))) {
  throw "Path is not a git repo: $RepoPath"
}

$dir = Split-Path -Path $ActiveRepoFilePath -Parent
if (-not [string]::IsNullOrWhiteSpace($dir)) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

Set-Content -LiteralPath $ActiveRepoFilePath -Value $RepoPath -Encoding UTF8
Write-Host "Active repo updated: $RepoPath"
Write-Host "File: $ActiveRepoFilePath"
