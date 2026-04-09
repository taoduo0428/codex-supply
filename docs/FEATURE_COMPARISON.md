# Feature Comparison: Default Codex vs This Enhanced Bundle

[English](./FEATURE_COMPARISON.md) | [简体中文](./FEATURE_COMPARISON.zh-CN.md)

This document answers a practical question: what is concretely improved compared with a default Codex setup.

Baseline definition:
- Default Codex: regular local usage without this repository's Win/WSL global bootstrap, governance runtime, plugin bundle, and automation layer.
- Enhanced bundle: setup performed through this repository's scripts and structure.

## High-level comparison

| Dimension | Default Codex (baseline) | This enhanced bundle | Practical impact |
| --- | --- | --- | --- |
| Team setup model | Commonly per-machine manual setup | Standard entry scripts: `win/bootstrap_fresh_global_full.ps1`, `wsl/bootstrap_fresh_global_full.sh` | Faster and more reproducible onboarding |
| Cross-platform parity | Windows/WSL drift is common | Windows + WSL script/document/validation parity | Fewer environment-specific surprises |
| Plugin distribution | Often ad-hoc/manual | 5-plugin global bundle via `common/claude-code-main/dist/global-plugins/index.json` | Auditable and consistent plugin set |
| MCP workspace wiring | Usually manual edits | Script-driven sync to config + plugin `.mcp.json` | Fewer broken-path runtime issues |
| Governance model | Mostly static prompt rules | Executable governance runtime (preflight/doctor/regression/project-contract/crawler-smoke) | Enforced checks, not just guidelines |
| Native hooks | Often absent or hand-maintained | Auto-managed `hooks.json` + `codex_hooks = true` | Pre-tool policy enforcement at runtime |
| Safety policy injection | Inconsistent and hard to track | Marker-based append into rules/AGENTS/ACTIVE | Non-destructive, upgradable policy baseline |
| Automation | Mostly manual operations | Daily smoke + optional git-review + optional nightly memory | Lower maintenance overhead |
| Advanced integrations | Higher setup friction | Auto-enabled from standard `external/*` layout (with optional source-path overrides) for `superpowers`, `OpenSpace`, self-improving, proactive; missing modules trigger submodule auto-init attempt by default | Modular upgrades without hard coupling |
| Open-source portability | Easy to leak machine-specific paths | Includes release + portability checklists | Better publish quality and teammate reuse |

## Detailed improvements with evidence paths

### 1) Standardized global bootstrap

- Windows entry: `win/bootstrap_fresh_global_full.ps1`
- WSL entry: `wsl/bootstrap_fresh_global_full.sh`
- Explicit parameter contract for `RepoRoot`, `WorkspacePath`, optional module paths, and skip flags.

### 2) Unified plugin/runtime asset delivery

- Plugin registry: `common/claude-code-main/dist/global-plugins/index.json`
- Installer: `common/claude-code-main/dist/global-plugins/install_global.ps1`
- Rollback: `common/claude-code-main/dist/global-plugins/rollback_global.ps1`
- Included plugins:
  - `workspace-core`
  - `git-review`
  - `agent-orchestration`
  - `integration-runtime`
  - `personal-productivity`

### 3) MCP and path wiring automation

The bootstrap syncs:
- `~/.codex/config.toml` (or `%USERPROFILE%\\.codex\\config.toml`)
- workspace-aware MCP fields in plugin `.mcp.json`
- `codex_hooks = true`

This reduces drift between plugin-level and global runtime config.

### 4) Executable governance runtime

The bundle creates and validates these tools (Windows/WSL variants):
- `codex_preflight_gate.*`
- `codex_doctor.*`
- `codex_regression_check.*`
- `codex_project_contract_init.*`
- `codex_project_contract_check.*`
- `codex_crawler_project_init.*`
- `codex_crawler_smoke_test.*`
- `codex_native_governance_hook.*`

### 5) Hook-driven runtime enforcement

- Managed file: `~/.codex/hooks.json`
- Required feature flag: `codex_hooks = true`
- Hook events include `SessionStart`, `UserPromptSubmit`, and `PreToolUse`

This enables runtime preflight checks before high-risk tool calls.

### 6) Non-destructive policy sync

- Rules baseline: `~/.codex/rules/default.rules`
- Agent/memory policy baselines: `~/.codex/AGENTS.md`, `~/.codex/memories/ACTIVE.md`
- Marker-based append strategy preserves existing user content.

### 7) Built-in operations automation

- Windows scripts: `common/claude-code-main/scripts/automation_*.ps1`
- WSL scripts: `wsl/automation/scripts/*.sh`
- Core operations:
  - smoke prompts
  - runtime validation
  - scheduled smoke
  - optional git review
  - optional nightly memory
  - proactive heartbeat (WSL)

### 8) Optional advanced modules

- `external/modules/mod-a`
- `external/modules/mod-b`
- `external/modules/mod-c`
- `external/modules/mod-d`

In standard bundle layout, modules are auto-enabled from `external/*`. If folders are missing, bootstrap auto-attempts `git submodule update --init --recursive` (unless skip-submodule-init is set). Source-path parameters are only needed as overrides for non-standard folder layouts.

### 9) Publish-ready documentation stack

- Teammate quickstarts: `win/TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md`, `wsl/TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md`
- Deep guides: `win/GLOBAL_BOOTSTRAP_TEAM_GUIDE.md`, `wsl/GLOBAL_BOOTSTRAP_TEAM_GUIDE.md`
- Release checks: `docs/RELEASE_CHECKLIST.md`
- Portability checks: `docs/PORTABILITY_CHECKS.md`

## Boundaries (to avoid over-promising)

These still depend on the end-user environment:
- OAuth/keyring login state (for example WSL `org.freedesktop.secrets` stack)
- real credentials (`GITHUB_TOKEN` / `GITHUB_PAT`)
- transient external service/network failures during smoke runs

These boundaries are documented in Win/WSL troubleshooting sections.

For plugin-level and script-level deep detail, see:
- `docs/FEATURE_MANUAL.md`
- `docs/FEATURE_MANUAL.zh-CN.md`

For public release scope boundary and submodule transparency rationale, see:
- `docs/PUBLISHING_MODEL.md`
- `docs/PUBLISHING_MODEL.zh-CN.md`
