# Teammate Global Setup Instructions (Windows)

Use this repository as a single bundle. Do not split `win/`, `wsl/`, `common/`, `external/`.

Publishing note:
- public release root = `GitHub上线`
- local development workspace `源码工程` is not part of public bundle contents

Read in order:
1. `win/TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md`
2. `win/GLOBAL_BOOTSTRAP_TEAM_GUIDE.md`
3. `win/bootstrap_fresh_global_full.ps1`

## Quick setup (edit only path block)

```powershell
# ===== Path parameters (edit only this block) =====
$BundleRoot = "C:\path\to\codex-bootstrap-bundle"
$RepoRoot = Join-Path $BundleRoot "common\claude-code-main"
$WorkspacePath = "C:\Users\<YOUR_USER>\Desktop\codex-workspace"
$BootstrapScript = Join-Path $BundleRoot "win\bootstrap_fresh_global_full.ps1"

# Optional: override module paths only when not using standard bundle layout.
# $SuperpowersSourcePath = "D:\custom\mod-a"
# $OpenSpaceSourcePath = "D:\custom\mod-b"
# $SelfImprovingSourcePath = "D:\custom\mod-c"
# $ProactiveSourcePath = "D:\custom\mod-d"

# ===== Pre-check =====
$required = @(
  $BootstrapScript,
  $RepoRoot,
  (Join-Path $RepoRoot "dist\global-plugins\index.json"),
  (Join-Path $RepoRoot "dist\global-plugins\install_global.ps1")
)
$missing = $required | Where-Object { -not (Test-Path -LiteralPath $_) }
if ($missing.Count -gt 0) {
  Write-Host "[ERROR] Missing paths:" -ForegroundColor Red
  $missing | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
  return
}

if (-not (Test-Path -LiteralPath $WorkspacePath)) {
  New-Item -ItemType Directory -Force -Path $WorkspacePath | Out-Null
}

# ===== Run global bootstrap =====
powershell -ExecutionPolicy Bypass -File $BootstrapScript `
  -RepoRoot $RepoRoot `
  -WorkspacePath $WorkspacePath `
  -DailySmokeTime "09:00" `
  -NightlyMemoryTime "01:30"

# Module behavior:
# - superpowers / OpenSpace / self-improving / proactive are auto-detected from "$BundleRoot\external\*"
# - if external modules are missing, script auto-attempts: git submodule update --init --recursive
# - only pass -<Module>SourcePath when your module folders are outside bundle/external
# Example (optional):
# -SuperpowersSourcePath $SuperpowersSourcePath
# -OpenSpaceSourcePath $OpenSpaceSourcePath
# -SelfImprovingSourcePath $SelfImprovingSourcePath
# -ProactiveSourcePath $ProactiveSourcePath
```

Do not pass `-Skip*` flags unless you intentionally want to disable that capability.

Automation defaults:

- `GitReview` is enabled by default.
- `NightlyMemory` is enabled by default.
- Use `-DisableGitReview` or `-DisableNightlyMemory` only if you intentionally want to turn them off.
- Use `-SkipSubmoduleInit` only if you intentionally do not want automatic submodule initialization.

Optional custom skills sync (only when you have a dedicated skills folder):

```powershell
$SkillsSourcePath = "C:\path\to\skills"
# then add:
# -SkillsSourcePath $SkillsSourcePath
```

## Required verification

```powershell
Write-Host "[VERIFY-1] Plugins / Skills" -ForegroundColor Cyan
Get-ChildItem "$env:USERPROFILE\.agents\plugins\plugins" -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
Get-ChildItem "$env:USERPROFILE\.agents\skills" -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name

Write-Host "[VERIFY-2] MCP + rules" -ForegroundColor Cyan
Select-String -Path "$env:USERPROFILE\.codex\config.toml" -Pattern '^\[mcp_servers\.(playwright|filesystem|fetch|git|openaiDeveloperDocs|openspace)\]$' -ErrorAction SilentlyContinue
Select-String -Path "$env:USERPROFILE\.codex\config.toml" -Pattern '^\s*codex_hooks\s*=\s*true\s*$' -ErrorAction SilentlyContinue
Select-String -Path "$env:USERPROFILE\.codex\rules\default.rules" -Pattern '^# codex-global-delete-guard:start$|^# codex-global-risk-guard:start$' -ErrorAction SilentlyContinue

Write-Host "[VERIFY-3] AGENTS / ACTIVE markers" -ForegroundColor Cyan
Select-String -Path "$env:USERPROFILE\.codex\AGENTS.md" -Pattern 'codex-global-(execution-policy|ml-active-trigger|reliability-policy|governance-policy|policy-runtime):start' -ErrorAction SilentlyContinue
Select-String -Path "$env:USERPROFILE\.codex\memories\ACTIVE.md" -Pattern 'codex-active-(execution-policy|reliability-policy|governance-policy|policy-runtime):start' -ErrorAction SilentlyContinue

Write-Host "[VERIFY-4] Governance runtime" -ForegroundColor Cyan
Test-Path "$env:USERPROFILE\.codex\runtime\governance\codex_preflight_gate.ps1"
Test-Path "$env:USERPROFILE\.codex\runtime\governance\codex_doctor.ps1"
Test-Path "$env:USERPROFILE\.codex\runtime\governance\codex_regression_check.ps1"
Test-Path "$env:USERPROFILE\.codex\hooks.json"

Write-Host "[VERIFY-5] Doctor + Regression" -ForegroundColor Cyan
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\runtime\governance\codex_doctor.ps1"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\runtime\governance\codex_regression_check.ps1" -BundleRoot $BundleRoot
```

Smoke prerequisites:

- `WorkspacePath` should be a trusted git repository path
- codex runtime must be authenticated (if stderr contains `401 Unauthorized: Missing bearer`, complete auth/login before rerun)
- transient API/network 5xx may cause temporary failures; retry after connectivity recovers

GitHub MCP token quick setup:

```powershell
[Environment]::SetEnvironmentVariable("GITHUB_TOKEN", "ghp_xxx", "User")
```

If you also use WSL and see keyring warnings (`org.freedesktop.secrets`):

```bash
bash ~/.agents/automation/scripts/setup_wsl_secret_service.sh
source ~/.bashrc
```
