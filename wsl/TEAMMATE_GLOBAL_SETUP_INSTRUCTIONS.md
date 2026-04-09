# Teammate Global Setup Instructions (WSL/Linux)

Use this repository as a single bundle. Do not split `win/`, `wsl/`, `common/`, `external/`.

Publishing note:
- public release root = `GitHub上线`
- local development workspace `源码工程` is not part of public bundle contents

Read in order:
1. `wsl/TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md`
2. `wsl/GLOBAL_BOOTSTRAP_TEAM_GUIDE.md`
3. `wsl/bootstrap_fresh_global_full.sh`

## Quick setup (edit only path block)

```bash
# ===== Path parameters (edit only this block) =====
BUNDLE_ROOT="/path/to/codex-bootstrap-bundle"
REPO_ROOT="$BUNDLE_ROOT/common/claude-code-main"
WORKSPACE_PATH="/path/to/your-main-workspace"

# Optional: override module paths only when not using standard bundle layout.
# SUPERPOWERS_SOURCE_PATH="/custom/mod-a"
# OPENSPACE_SOURCE_PATH="/custom/mod-b"
# SELF_IMPROVING_SOURCE_PATH="/custom/mod-c"
# PROACTIVE_SOURCE_PATH="/custom/mod-d"

# ===== Pre-check =====
required=(
  "$BUNDLE_ROOT/wsl/bootstrap_fresh_global_full.sh"
  "$REPO_ROOT"
  "$REPO_ROOT/dist/global-plugins/index.json"
)

missing=0
for p in "${required[@]}"; do
  if [[ ! -e "$p" ]]; then
    echo "[ERROR] Missing: $p"
    missing=1
  fi
done
[[ "$missing" -eq 0 ]] || exit 1

mkdir -p "$WORKSPACE_PATH"
chmod +x "$BUNDLE_ROOT/wsl/bootstrap_fresh_global_full.sh"

# ===== Run global bootstrap =====
bash "$BUNDLE_ROOT/wsl/bootstrap_fresh_global_full.sh" \
  --repo-root "$REPO_ROOT" \
  --workspace-path "$WORKSPACE_PATH" \
  --daily-smoke-time "09:00" \
  --nightly-memory-time "01:30"

# Module behavior:
# - superpowers / OpenSpace / self-improving / proactive are auto-detected from "$BUNDLE_ROOT/external/*"
# - if external modules are missing, script auto-attempts: git submodule update --init --recursive
# - only pass --*-source-path when module folders are outside bundle/external
# Example (optional):
# --superpowers-source-path "$SUPERPOWERS_SOURCE_PATH" \
# --openspace-source-path "$OPENSPACE_SOURCE_PATH" \
# --self-improving-source-path "$SELF_IMPROVING_SOURCE_PATH" \
# --proactive-source-path "$PROACTIVE_SOURCE_PATH"
```

Do not pass `--skip-*` flags unless you intentionally want to disable that capability.

Automation defaults:

- `GitReview` is enabled by default.
- `NightlyMemory` is enabled by default.
- Use `--disable-git-review` or `--disable-nightly-memory` only if you intentionally want to turn them off.
- Use `--skip-submodule-init` only if you intentionally do not want automatic submodule initialization.

Optional custom skills sync (only when you have a dedicated skills folder):

```bash
SKILLS_SOURCE_PATH="/path/to/skills"
# then add:
# --skills-source-path "$SKILLS_SOURCE_PATH"
```

## Required verification

```bash
# 1) Plugins / skills
ls -1 ~/.agents/plugins/plugins
ls -1 ~/.agents/skills

# 2) MCP + hooks + rules
grep -nE '^\[mcp_servers\.(playwright|filesystem|fetch|git|openaiDeveloperDocs|openspace)\]$' ~/.codex/config.toml
grep -nE '^\s*codex_hooks\s*=\s*true\s*$' ~/.codex/config.toml
grep -nE '^# codex-global-delete-guard:start$|^# codex-global-risk-guard:start$' ~/.codex/rules/default.rules

# 3) AGENTS / ACTIVE markers
grep -nE 'codex-global-(execution-policy|ml-active-trigger|reliability-policy|governance-policy|policy-runtime):start' ~/.codex/AGENTS.md
grep -nE 'codex-active-(execution-policy|reliability-policy|governance-policy|policy-runtime):start' ~/.codex/memories/ACTIVE.md

# 4) Governance scripts + hooks + runtime checks
ls -1 ~/.codex/runtime/governance
grep -n 'codex_native_governance_hook.sh' ~/.codex/hooks.json
bash ~/.codex/runtime/governance/codex_doctor.sh --codex-home ~/.codex
bash ~/.codex/runtime/governance/codex_regression_check.sh --codex-home ~/.codex --bundle-root "$BUNDLE_ROOT"

# 5) Automation runtime
bash ~/.agents/automation/scripts/validate_global_runtime.sh --expected-workspace-path "$WORKSPACE_PATH"
bash ~/.agents/automation/scripts/run_smoke_prompts.sh --workspace-path "$WORKSPACE_PATH" --timeout-seconds 120 --retry-attempts 2
```

Smoke prerequisites:

- `WORKSPACE_PATH` should point to a trusted git repository
- codex runtime must be authenticated (if stderr contains `401 Unauthorized: Missing bearer`, complete auth/login before rerun)
- transient API/network 5xx may cause temporary failures; retry after connectivity recovers

GitHub MCP token:

```bash
cp ~/.agents/automation/.env.example ~/.agents/automation/.env
chmod 600 ~/.agents/automation/.env
# edit ~/.agents/automation/.env and set GITHUB_TOKEN or GITHUB_PAT
```

If WSL shows keyring warnings (`org.freedesktop.secrets`):

```bash
bash ~/.agents/automation/scripts/setup_wsl_secret_service.sh
source ~/.bashrc
```

Windows path note: this bootstrap also accepts Windows-style paths (`C:\Users\...`) and auto-converts in WSL.
