# Global Codex Bootstrap Guide (Windows)

This guide bootstraps Codex global runtime from this open-source bundle layout:

- `win/` Windows scripts and docs
- `wsl/` Linux/WSL scripts and docs
- `common/claude-code-main/` shared runtime assets (required)
- `external/*` optional enhanced modules (via git submodule)

Release boundary note:

- Public GitHub release should use `GitHub上线` as repository root.
- `源码工程` is local development workspace and should not be published as bundle content.
- Full boundary rationale: `docs/PUBLISHING_MODEL.md` and `docs/PUBLISHING_MODEL.zh-CN.md`.

## What this bootstrap does

Main script: `win/bootstrap_fresh_global_full.ps1`

It installs/syncs:

- global plugins to `%USERPROFILE%\.agents\plugins\plugins`
- automation scripts to `%USERPROFILE%\.agents\automation\scripts`
- optional skills from `-SkillsSourcePath`
- optional `superpowers`, `OpenSpace`, self-improving, proactive integrations
- MCP baseline into `%USERPROFILE%\.codex\config.toml`
- policy markers into `%USERPROFILE%\.codex\AGENTS.md` and `%USERPROFILE%\.codex\memories\ACTIVE.md`
- governance scripts into `%USERPROFILE%\.codex\runtime\governance`
- native hooks into `%USERPROFILE%\.codex\hooks.json`

It is append/backup oriented and does not bulk-delete user files.

## Prerequisites

Required:

- `git`
- `node` + `npx`
- `py` (Python launcher)
- PowerShell 5.1+ (or PowerShell 7+)

Recommended:

- `pre-commit`
- `GITHUB_TOKEN` for GitHub MCP

## Clone with submodules (recommended)

```powershell
git clone <YOUR_REPO_URL> codex-bootstrap
cd codex-bootstrap
git submodule update --init --recursive
```

If this step is skipped, bootstrap will auto-attempt the same submodule command when it detects missing `external/*` modules.

## One-shot bootstrap command

```powershell
$BundleRoot = "C:\path\to\codex-bootstrap"

powershell -ExecutionPolicy Bypass -File "$BundleRoot\win\bootstrap_fresh_global_full.ps1" `
  -RepoRoot "$BundleRoot\common\claude-code-main" `
  -WorkspacePath "C:\path\to\your-main-workspace" `
  -DailySmokeTime "09:00" `
  -NightlyMemoryTime "01:30"
```

If a teammate uses different drives or folders, only change argument values. Do not edit script internals.

Default module behavior:

- `superpowers`, `OpenSpace`, `self-improving`, `proactive` are auto-discovered from `$BundleRoot\external\*` and enabled by default when present.
- If those module folders are missing, bootstrap auto-attempts `git submodule update --init --recursive`.
- You only need `-<Module>SourcePath` when module folders are outside the standard bundle layout.

Terminology clarification:

- "Optional modules" means optional in distribution scope (you may include/exclude them from the repository package).
- "Default enabled" means runtime behavior (if included and present in standard paths, bootstrap enables them automatically).

Default automation behavior:

- `GitReview` scheduled task is enabled by default.
- `NightlyMemory` scheduled task is enabled by default.
- You can disable them with `-DisableGitReview` / `-DisableNightlyMemory`.

Optional custom skills sync (only if you maintain a dedicated skills folder):

```powershell
-SkillsSourcePath "C:\path\to\skills"
```

Optional module source overrides (non-standard layout only):

```powershell
-SuperpowersSourcePath "D:\custom\mod-a" `
-OpenSpaceSourcePath "D:\custom\mod-b" `
-SelfImprovingSourcePath "D:\custom\mod-c" `
-ProactiveSourcePath "D:\custom\mod-d"
```

## Optional flags

Skip flags (default is sync enabled):

- `-SkipCodexConfigSync`
- `-SkipSafetyPolicySync`
- `-SkipOpenSpaceSync`
- `-SkipGovernanceToolkitSync`
- `-SkipNativeHooksSync`
- `-SkipSubmoduleInit`
- `-SkipScheduledTasks`

Other flags:

- `-UseSymlink`
- `-EnableGitReview` (kept for compatibility; already default-on)
- `-DisableGitReview`
- `-EnableNightlyMemory` (kept for compatibility; already default-on)
- `-DisableNightlyMemory`
- `-GitReviewIntervalHours N`
- `-GitReviewTimeoutSeconds N`

## Validation after install

```powershell
# tasks
Get-ScheduledTask -TaskName "Codex-Auto-Daily-Smoke","Codex-Auto-Git-Review","Codex-Auto-Nightly-Memory" -ErrorAction SilentlyContinue |
  Select-Object TaskName,State | Format-Table -AutoSize

# plugins/skills
Get-ChildItem "$env:USERPROFILE\.agents\plugins\plugins" -Directory | Select-Object Name
Get-ChildItem "$env:USERPROFILE\.agents\skills" -Directory | Select-Object Name

# config/rules/markers
Select-String -Path "$env:USERPROFILE\.codex\config.toml" -Pattern '^\[mcp_servers\.(playwright|filesystem|fetch|git|openaiDeveloperDocs|openspace)\]$'
Select-String -Path "$env:USERPROFILE\.codex\config.toml" -Pattern '^\s*codex_hooks\s*=\s*true\s*$'
Select-String -Path "$env:USERPROFILE\.codex\rules\default.rules" -Pattern '^# codex-global-delete-guard:start$|^# codex-global-risk-guard:start$'
Select-String -Path "$env:USERPROFILE\.codex\AGENTS.md" -Pattern 'codex-global-(execution-policy|ml-active-trigger|reliability-policy|governance-policy|policy-runtime):start'
Select-String -Path "$env:USERPROFILE\.codex\memories\ACTIVE.md" -Pattern 'codex-active-(execution-policy|reliability-policy|governance-policy|policy-runtime):start'

# governance runtime
Test-Path "$env:USERPROFILE\.codex\runtime\governance\codex_preflight_gate.ps1"
Test-Path "$env:USERPROFILE\.codex\runtime\governance\codex_doctor.ps1"
Test-Path "$env:USERPROFILE\.codex\runtime\governance\codex_regression_check.ps1"
Test-Path "$env:USERPROFILE\.codex\hooks.json"

# doctor + regression
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\runtime\governance\codex_doctor.ps1"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\runtime\governance\codex_regression_check.ps1" -BundleRoot $BundleRoot
```

Smoke prerequisites (when running smoke scripts):

- `WorkspacePath` should point to a trusted git repository
- codex runtime must be authenticated (if stderr shows `401 Unauthorized: Missing bearer`, fix auth/login first)
- transient API/network 5xx can cause temporary smoke failures; retry later

## Troubleshooting

If teammate reports missing MCP/plugins/skills:

- confirm script is `win/bootstrap_fresh_global_full.ps1`
- confirm `-RepoRoot` is `...\common\claude-code-main`
- confirm submodules initialized (`git submodule update --init --recursive`)
- if you intentionally passed `-SkipSubmoduleInit`, remove it and rerun
- confirm no accidental `-Skip*` flags
- rerun doctor + regression
- restart Codex/IDE session

If OpenSpace not available:

- check `external\modules\mod-b` exists
- check `-OpenSpaceSourcePath` points to it

If GitHub MCP auth is missing:

```powershell
[Environment]::SetEnvironmentVariable("GITHUB_TOKEN", "ghp_xxx", "User")
```
