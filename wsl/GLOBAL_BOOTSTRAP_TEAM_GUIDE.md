# Global Codex Bootstrap Guide (WSL/Linux)

This guide explains how to bootstrap Codex global runtime from this open-source bundle layout:

- `wsl/` Linux scripts and docs
- `win/` Windows scripts and docs
- `common/claude-code-main/` shared runtime assets (required)
- `external/*` optional enhanced modules (via git submodule)

Release boundary note:

- Public GitHub release should use `GitHub上线` as repository root.
- `源码工程` is local development workspace and should not be published as bundle content.
- Full boundary rationale: `docs/PUBLISHING_MODEL.md` and `docs/PUBLISHING_MODEL.zh-CN.md`.

## What the WSL bootstrap installs

Script: `wsl/bootstrap_fresh_global_full.sh`

It syncs these user-level targets:

- `~/.agents/plugins/plugins/*` and `~/.agents/plugins/marketplace.json`
- `~/.agents/automation/scripts/*` (+ `README.md`, `.env.example`)
- optional global skills from `--skills-source-path`
- optional `superpowers` mirror to `~/.codex/superpowers`
- optional `OpenSpace` mirror to `~/.codex/openspace`
- optional self-improving runtime to `~/.codex/self-improving-for-codex`
- global MCP baseline in `~/.codex/config.toml`
- policy markers in `~/.codex/AGENTS.md` and `~/.codex/memories/ACTIVE.md`
- governance runtime in `~/.codex/runtime/governance`
- native hooks in `~/.codex/hooks.json`

## Prerequisites

Required commands:

- `bash`
- `python3`
- `git`
- `node`
- `npx`

Recommended:

- `pre-commit`
- `crontab`

## Clone with submodules (recommended)

```bash
git clone <YOUR_REPO_URL> codex-bootstrap
cd codex-bootstrap
git submodule update --init --recursive
```

If this step is skipped, bootstrap will auto-attempt the same submodule command when missing `external/*` modules are detected.

## One-shot bootstrap command

```bash
BUNDLE_ROOT="/path/to/codex-bootstrap"

bash "$BUNDLE_ROOT/wsl/bootstrap_fresh_global_full.sh" \
  --repo-root "$BUNDLE_ROOT/common/claude-code-main" \
  --workspace-path "/path/to/your-main-workspace" \
  --daily-smoke-time 09:00 \
  --nightly-memory-time 01:30
```

Windows path compatibility: this script accepts `C:\Users\<YOUR_USER>\...` style paths and auto-converts in WSL.

Default module behavior:

- `superpowers`, `OpenSpace`, `self-improving`, `proactive` are auto-discovered from `$BUNDLE_ROOT/external/*` and enabled by default when present.
- If those module folders are missing, bootstrap auto-attempts `git submodule update --init --recursive`.
- You only need `--*-source-path` overrides when module folders are outside the standard bundle layout.

Terminology clarification:

- "Optional modules" means optional in distribution scope (you may include/exclude them from the repository package).
- "Default enabled" means runtime behavior (if included and present in standard paths, bootstrap enables them automatically).

Default automation behavior:

- `GitReview` cron task is enabled by default.
- `NightlyMemory` cron task is enabled by default.
- You can disable them with `--disable-git-review` / `--disable-nightly-memory`.

Optional custom skills sync (only if you maintain a dedicated skills folder):

```bash
--skills-source-path "/path/to/skills"
```

Optional module source overrides (non-standard layout only):

```bash
--superpowers-source-path "/custom/mod-a" \
--openspace-source-path "/custom/mod-b" \
--self-improving-source-path "/custom/mod-c" \
--proactive-source-path "/custom/mod-d"
```

## Optional flags

Skip flags (default is enabled):

- `--skip-codex-config-sync`
- `--skip-safety-policy-sync`
- `--skip-openspace-sync`
- `--skip-governance-toolkit-sync`
- `--skip-native-hooks-sync`
- `--skip-submodule-init`
- `--skip-scheduled-tasks`

Other flags:

- `--use-symlink`
- `--enable-git-review` (kept for compatibility; already default-on)
- `--disable-git-review`
- `--enable-nightly-memory` (kept for compatibility; already default-on)
- `--disable-nightly-memory`
- `--git-review-interval-hours N`
- `--git-review-timeout-seconds N`

## Validation after install

```bash
# plugins/skills
ls -1 ~/.agents/plugins/plugins
ls -1 ~/.agents/skills

# config + rules + markers
grep -nE '^\[mcp_servers\.(playwright|filesystem|fetch|git|openaiDeveloperDocs|openspace)\]$' ~/.codex/config.toml
grep -nE '^\s*codex_hooks\s*=\s*true\s*$' ~/.codex/config.toml
grep -nE '^# codex-global-delete-guard:start$|^# codex-global-risk-guard:start$' ~/.codex/rules/default.rules
grep -nE 'codex-global-(execution-policy|ml-active-trigger|reliability-policy|governance-policy|policy-runtime):start' ~/.codex/AGENTS.md
grep -nE 'codex-active-(execution-policy|reliability-policy|governance-policy|policy-runtime):start' ~/.codex/memories/ACTIVE.md

# governance runtime + hooks
ls -1 ~/.codex/runtime/governance
grep -n 'codex_native_governance_hook.sh' ~/.codex/hooks.json

# doctor + regression
bash ~/.codex/runtime/governance/codex_doctor.sh --codex-home ~/.codex
bash ~/.codex/runtime/governance/codex_regression_check.sh --codex-home ~/.codex --bundle-root "$BUNDLE_ROOT"

# automation runtime
bash ~/.agents/automation/scripts/validate_global_runtime.sh --expected-workspace-path "/path/to/your-main-workspace"
bash ~/.agents/automation/scripts/run_smoke_prompts.sh --workspace-path "/path/to/your-main-workspace" --timeout-seconds 120 --retry-attempts 2
```

Smoke prerequisites:

- workspace should be a trusted git repository path
- codex runtime must be authenticated (if stderr shows `401 Unauthorized: Missing bearer`, fix auth first)
- transient `wss://api.openai.com/v1/responses` 5xx can cause temporary smoke failures; retry after network/service recovery

## Credentials and keyring

GitHub MCP token:

```bash
cp ~/.agents/automation/.env.example ~/.agents/automation/.env
chmod 600 ~/.agents/automation/.env
# set GITHUB_TOKEN or GITHUB_PAT
```

WSL keyring fix (for `org.freedesktop.secrets` warnings):

```bash
bash ~/.agents/automation/scripts/setup_wsl_secret_service.sh
source ~/.bashrc
```

## Troubleshooting

If teammate reports missing MCP/plugins/skills:

- confirm they ran `wsl/bootstrap_fresh_global_full.sh`
- confirm `--repo-root` points to `common/claude-code-main`
- confirm submodules are initialized (`git submodule update --init --recursive`)
- if you intentionally passed `--skip-submodule-init`, remove it and rerun
- confirm no accidental `--skip-*` flags
- rerun doctor + regression
- restart Codex session after bootstrap

If OpenSpace not available:

- check `external/modules/mod-b` exists
- check `--openspace-source-path` points to that folder

If cron jobs not created:

- check `crontab` exists
- rerun bootstrap without `--skip-scheduled-tasks`
