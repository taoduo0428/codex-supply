# Full Feature Manual (Detailed)

[English](./FEATURE_MANUAL.md) | [简体中文](./FEATURE_MANUAL.zh-CN.md)

This is the release-grade feature ledger for the bundle. It answers:
1. What capabilities are included.
2. What is auto-enabled by default.
3. What still depends on user credentials or environment.

## 1) Auto-enable matrix

| Capability | Default state | Auto-enable condition | Still manual when... |
| --- | --- | --- | --- |
| Global plugin install (5 plugins) | Enabled | `RepoRoot` provided or auto-resolved to `common/claude-code-main` | layout is non-standard and cannot be resolved |
| `superpowers` module | Enabled | `external/modules/mod-a` exists | module is outside standard layout |
| `OpenSpace` module | Enabled | `external/modules/mod-b` exists and host skills are present | non-standard path or incomplete host skills |
| `self-improving` module | Enabled | `external/modules/mod-c` exists | non-standard path or missing scripts |
| `proactive` module | Enabled (metadata/runtime scaffolding) | `external/modules/mod-d` exists | non-standard path |
| external module submodule init | Auto-attempt | missing `external/*` modules + bundle root is a git repo + git available | user passes skip-submodule-init flag, or no git/network |
| GitReview automation | Enabled | not explicitly disabled | user chooses to disable |
| NightlyMemory automation | Enabled | not explicitly disabled and pipeline script exists | disabled explicitly or script missing |
| rules/AGENTS/ACTIVE policy sync | Enabled | skip flags not used | user passes skip flags |
| Native hooks wiring | Enabled | skip flags not used | user passes native-hooks skip flag |
| WSL secret-service quick init | Auto-attempt (non-blocking) | setup script exists | dependencies still need manual install |

Terminology note:
- "Optional module" refers to distribution scope (you may choose to include or exclude module sources).
- "Enabled by default" refers to runtime behavior (if module sources exist in standard paths, bootstrap enables them automatically).

## 2) Capabilities that still require user action

These are expected and not a migration flaw:

1. Credentials: `GITHUB_TOKEN` / `GITHUB_PAT`.
2. OAuth/keyring login state (for example WSL `org.freedesktop.secrets` stack).
3. Custom source paths when using non-standard repository layout.
4. Workspace selection (auto fallback exists, but explicit workspace path is still recommended for team predictability).

## 3) Plugin capability catalog (5 plugins)

Source directory: `common/claude-code-main/dist/global-plugins`

### 3.1 `workspace-core`

- Responsibility boundary:
  repository exploration, status/context diagnostics, and session hygiene.
- Best trigger scenarios:
  "scan this repo first", "summarize current workspace risk", "clean session state before coding".
- Example prompts:
  - `Scan this repository and summarize current risks before coding.`
  - `List changed files and context pressure in this session.`
  - `Compact this session without dropping unresolved blockers.`
- Required dependencies:
  accessible workspace path and standard repository read access.
- Typical outputs:
  workspace summary, risk shortlist, and next-step orientation.
- Common misunderstanding:
  this plugin does not replace review/release gates; it provides baseline orientation.
- Troubleshooting checks:
  verify workspace path is correct and repository is readable.

### 3.2 `git-review`

- Responsibility boundary:
  diff review, commit hygiene, PR readiness, and pre-release gate checks.
- Best trigger scenarios:
  "prepare this branch for PR", "review diff risks", "is this release-ready".
- Example prompts:
  - `Review this diff and suggest commit boundaries.`
  - `Create a PR-ready summary with risks and test notes.`
  - `Run a release-go/no-go checklist for this branch.`
- Required dependencies:
  valid git repo with readable history and diff.
- Typical outputs:
  commit split recommendations, reviewer summary, release risk notes.
- Common misunderstanding:
  it cannot prove production safety alone; CI and integration tests remain mandatory.
- Troubleshooting checks:
  ensure repository is trusted, git history is accessible, and target branch context is known.

### 3.3 `agent-orchestration`

- Responsibility boundary:
  task decomposition, execution sequencing, and parallel ownership planning.
- Best trigger scenarios:
  "split this into phases", "parallelize safely", "define execution gates".
- Example prompts:
  - `Break this feature into executable phases with dependencies.`
  - `Split this refactor into non-overlapping workstreams.`
  - `Define checkpoints and verification gates for delivery.`
- Required dependencies:
  clear objective and scope constraints.
- Typical outputs:
  phase plan, ownership map, and verification checkpoints.
- Common misunderstanding:
  orchestration quality follows requirement clarity; vague goals produce vague plans.
- Troubleshooting checks:
  tighten scope statement and explicit constraints before re-running decomposition.

### 3.4 `integration-runtime`

- Responsibility boundary:
  MCP/runtime bootstrap, connector diagnostics, and integration consistency checks.
- Best trigger scenarios:
  "set up MCP", "why this connector fails", "align runtime config".
- Example prompts:
  - `Bootstrap MCP servers for this workspace and verify connectivity.`
  - `Diagnose why github MCP is not available.`
  - `Check runtime wiring consistency across config and plugins.`
- Required dependencies:
  runtime binaries (`node`, `npx`, MCP tools), network reachability, and credentials for token-protected connectors.
- Typical outputs:
  config patch suggestions, health-check results, dependency gap report.
- Common misunderstanding:
  wiring success does not imply auth success; token/OAuth state is still required.
- Troubleshooting checks:
  validate token envs, keyring state, and connector-specific prerequisites.
- MCP baseline wiring includes:
  `playwright`, `filesystem`, `fetch`, `git`, `github` (token-dependent), `openaiDeveloperDocs`.

### 3.5 `personal-productivity`

- Responsibility boundary:
  verify-debug closure loops and memory curation for repeatable execution quality.
- Best trigger scenarios:
  "verify then fix", "stabilize repeated failures", "promote reusable memory".
- Example prompts:
  - `Run a verify-debug loop until pass criteria are met.`
  - `Summarize unresolved risks after this fix cycle.`
  - `Promote durable memory entries and remove stale ones.`
- Required dependencies:
  reproducible checks (test/lint/build/smoke) and observable failure signals.
- Typical outputs:
  pass/fail criteria, loop results, residual risk list, memory updates.
- Common misunderstanding:
  memory curation is not a replacement for deterministic tests.
- Troubleshooting checks:
  define explicit pass criteria and ensure at least one reproducible validation path.

### 3.6 Runtime wiring detail by plugin (actual files)

Source evidence:
- `common/claude-code-main/dist/global-plugins/<plugin>/.mcp.json`
- `common/claude-code-main/dist/global-plugins/<plugin>/hooks.json`
- `common/claude-code-main/dist/global-plugins/<plugin>/.app.json`

Observed runtime shape:
- `workspace-core`: no plugin-local MCP servers, no plugin-local hooks, no app entries.
- `git-review`: no plugin-local MCP servers, no plugin-local hooks, no app entries.
- `agent-orchestration`: no plugin-local MCP servers, no plugin-local hooks, no app entries.
- `personal-productivity`: no plugin-local MCP servers, no plugin-local hooks, no app entries.
- `integration-runtime`: contains the MCP baseline (`playwright`, `filesystem`, `fetch`, `git`, `github`, `openaiDeveloperDocs`).

Practical meaning:
- Most runtime integration is intentionally centralized in `integration-runtime` for easier debugging.
- `github` server capability is wired by config, but real availability still depends on user token (`GITHUB_TOKEN` / `GITHUB_PAT`).
- Hook execution is provided by global native hook wiring (`~/.codex/hooks.json`), not per-plugin hook arrays.

## 4) Windows script catalog

Directory: `common/claude-code-main/scripts`

| Script | Purpose | Key inputs | Key outputs |
| --- | --- | --- | --- |
| `bootstrap_fresh_global_full.ps1` | full global bootstrap entrypoint | RepoRoot/WorkspacePath + optional overrides | plugins, MCP wiring, policies, hooks, automations |
| `validate_global_runtime.ps1` | runtime health check | expected workspace (optional) | PASS/FAIL checks |
| `run_smoke_prompts.ps1` | 5-domain smoke suite | workspace, timeout, retry | per-case logs and verdicts |
| `setup_automations.ps1` | register scheduled tasks | schedule intervals/timeouts | daily smoke + git review tasks |
| `automation_daily_smoke.ps1` | daily validation + smoke chain | workspace + timeout | automation log files |
| `automation_git_review.ps1` | automated review report generation | workspace + timeout | review markdown report |
| `set_active_repo.ps1` | set active repo pointer | repo path | `~/.agents/active-repo.txt` |
| `remove_automations.ps1` | remove scheduled tasks | none | task cleanup |
| `bootstrap_fresh_global.ps1` | compact bootstrap variant | core parameters | baseline setup |

## 5) WSL script catalog

Directory: `wsl/automation/scripts`

| Script | Purpose | Key inputs | Key outputs |
| --- | --- | --- | --- |
| `validate_global_runtime.sh` | runtime health check | expected workspace | PASS/FAIL checks |
| `run_smoke_prompts.sh` | smoke test with retry control | workspace/timeout/retry | case-level logs and summary |
| `automation_daily_smoke.sh` | daily validation + smoke | workspace + timeout | logs/daily-smoke-* |
| `automation_git_review.sh` | automated git review report | workspace + timeout | reports/git-review-* |
| `automation_self_improve_nightly.sh` | nightly memory pipeline executor | self-improving pipeline script | status + logs |
| `automation_proactive_heartbeat.sh` | proactive heartbeat + risk signals | threshold options | heartbeat JSON/context |
| `setup_automations.sh` | cron registration | times/intervals/switches | cron tasks |
| `setup_wsl_secret_service.sh` | keyring setup in WSL | install/shell options | secret-service init configuration |
| `setup_proactive_heartbeat_task.sh` | dedicated heartbeat cron setup | interval | cron entry |
| `set_active_repo.sh` | active repo pointer update | repo path | `~/.agents/active-repo.txt` |
| `remove_automations.sh` | remove automation cron entries | none | cron cleanup |
| `common.sh` | shared runtime utilities | env + optional `.env` | reusable helper functions |

## 6) Governance runtime capabilities

Target directory: `~/.codex/runtime/governance`

Delivered tools:
- `codex_preflight_gate.*`
- `codex_doctor.*`
- `codex_regression_check.*`
- `codex_project_contract_init.*`
- `codex_project_contract_check.*`
- `codex_crawler_project_init.*`
- `codex_crawler_smoke_test.*`
- `codex_native_governance_hook.*`

Coupled runtime wiring:
- `~/.codex/hooks.json` is managed for native hook dispatch.
- `~/.codex/config.toml` includes `codex_hooks = true`.

## 7) Default bootstrap flow

1. Parse args and auto-resolve standard bundle paths.
2. Install global plugins and register marketplace entries.
3. Sync MCP/config wiring (workspace and optional OpenSpace environment).
4. Sync safety policy blocks into rules/AGENTS/ACTIVE markers.
5. Register automations (daily smoke + git review + nightly memory by default).
6. Sync governance toolkit and native hooks.
7. Run doctor/regression/smoke checks according to installed runtime.

## 8) One-line positioning

Default Codex is usually session-centric with manual environment care.  
This bundle is a reproducible global runtime package with executable governance and automation loops.
