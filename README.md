# Codex Global Bootstrap Bundle

[English](./README.md) | [简体中文](./README.zh-CN.md)

Cross-platform bootstrap bundle for Codex global runtime.

This repository provides a portable team setup for Windows + WSL/Linux, with shared runtime assets and optional enhanced modules via Git submodules.

## Repository layout

- `win/`: Windows bootstrap script + teammate docs
- `wsl/`: WSL/Linux bootstrap script + teammate docs + automation scripts
- `common/claude-code-main/`: required shared runtime assets
- `external/`: optional enhanced modules (git submodules)
- `docs/`: release and portability docs

## Included capabilities

- Global plugin install (`workspace-core`, `git-review`, `agent-orchestration`, `integration-runtime`, `personal-productivity`)
- Global automation scripts (smoke / validation / scheduled jobs)
- Global MCP baseline sync and workspace wiring
- Governance runtime scripts (preflight / doctor / regression / project-contract)
- Optional `superpowers`, `OpenSpace`, self-improving, proactive modules

## 5 Global Plugins At A Glance

| Plugin | Primary role | Typical trigger | Input dependencies | Typical output | Limits |
| --- | --- | --- | --- | --- | --- |
| `workspace-core` | workspace/session foundation | "scan repo status", "clean session context" | readable workspace path | repo status/risk summary, context hygiene actions | does not replace domain-specific review or release checks |
| `git-review` | code review + release gate | "prepare PR", "review this diff", "ship check" | git repository + accessible diff history | commit boundary suggestions, PR-ready summary, release risk notes | not a substitute for full CI/integration tests |
| `agent-orchestration` | planning + decomposition | "split task", "build phased plan", "parallelize work" | clear task objective and constraints | phased execution plan, ownership split, verification gates | plan quality depends on requirement clarity |
| `integration-runtime` | MCP/runtime wiring and diagnostics | "set up MCP", "why tool cannot connect" | runtime binaries (`node`, `npx`, MCP servers), optional tokens | runtime config patches, connectivity diagnosis, MCP capability map | external connectors still depend on credentials/network |
| `personal-productivity` | verify-debug loop + memory curation | "verify then fix", "turn process into reusable rule" | reproducible checks and observable failures | failure map, verify-debug loop, reusable memory updates | cannot compensate for missing tests or missing reproducibility |

## Terminology: Optional vs Default-Enabled

- Optional integration modules:
  `superpowers`, `OpenSpace`, `self-improving`, and `proactive` are optional in packaging terms. You may choose to include or exclude them from the repository distribution.
- Default-enabled behavior:
  if these modules exist in standard `external/*` paths, bootstrap auto-discovers and enables them by default during runtime setup.

## What is improved vs default Codex setup

Baseline used here: "default Codex setup" means a normal local install without this repository's global bootstrap scripts, governance runtime, and plugin bundle.

1. Reproducible team bootstrap instead of per-machine manual setup.
2. Cross-platform parity (Windows + WSL/Linux) with equivalent bootstrap flow and checks.
3. Pre-packaged global plugin suite (5 plugins) instead of ad-hoc plugin installation.
4. Workspace-aware MCP wiring is auto-synced into config and plugin MCP files.
5. Runtime governance is executable (preflight gate, doctor, regression), not only prompt rules.
6. Native hook integration (`PreToolUse`/`SessionStart`/`UserPromptSubmit`) is auto-managed.
7. Safety/risk guard policy blocks are inserted into rules/AGENTS/ACTIVE with marker-based append.
8. Automation layer is included (daily smoke, optional git-review, optional nightly memory).
9. Advanced modules are auto-enabled from `external/*` by default (`superpowers`, `OpenSpace`, self-improving, proactive), with optional path overrides.
10. Release portability/security checklists are included for open-source handoff.

Detailed comparison with evidence paths:

- `docs/FEATURE_COMPARISON.md`
- `docs/FEATURE_COMPARISON.zh-CN.md`

## User-specific configuration checklist

Every user must replace placeholders based on their own machine.

| Parameter | Example placeholder | Required |
| --- | --- | --- |
| Bundle root path | `C:\path\to\codex-bootstrap` / `/path/to/codex-bootstrap` | Yes |
| Workspace path | `C:\path\to\your-main-workspace` / `/path/to/your-main-workspace` | Yes |
| Repo URL | `<YOUR_REPO_URL>` | Yes |
| Optional skills path | `C:\path\to\skills` / `/path/to/skills` | No |
| Optional module source overrides | `-SuperpowersSourcePath ...` / `--superpowers-source-path ...` (and peers) | No |
| GitHub token (`GITHUB_TOKEN`/`GITHUB_PAT`) | `ghp_xxx` (placeholder only) | Recommended |

## Quick start

### 1) Clone and init submodules (recommended)

```bash
git clone <YOUR_REPO_URL> codex-bootstrap
cd codex-bootstrap
git submodule update --init --recursive
```

If you skip this step, bootstrap will still auto-attempt submodule initialization when `external/*` modules are missing.

### 2) Run bootstrap

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\win\bootstrap_fresh_global_full.ps1 `
  -RepoRoot ".\common\claude-code-main" `
  -WorkspacePath "C:\path\to\your-main-workspace"
```

WSL/Linux:

```bash
bash ./wsl/bootstrap_fresh_global_full.sh \
  --repo-root "./common/claude-code-main" \
  --workspace-path "/path/to/your-main-workspace"
```

Default behavior:

- The bootstrap auto-discovers and enables `superpowers`, `OpenSpace`, `self-improving`, and `proactive` from `./external/*` when those folders exist.
- If those module folders are missing, bootstrap auto-attempts `git submodule update --init --recursive`.
- You only need module source args when your folders are in non-standard locations.
- `GitReview` and `NightlyMemory` automations are enabled by default.
- Use `-DisableGitReview` / `--disable-git-review` and `-DisableNightlyMemory` / `--disable-nightly-memory` only when you intentionally want them off.
- Use `-SkipSubmoduleInit` / `--skip-submodule-init` only when you intentionally do not want automatic submodule init.

Optional custom skills sync (only when you have a dedicated skills folder):

- Windows: add `-SkillsSourcePath "C:\path\to\skills"`
- WSL/Linux: add `--skills-source-path "/path/to/skills"`

Smoke/validation note:

- `run_smoke_prompts` requires a trusted git workspace and authenticated codex runtime.
- If logs show `401 Unauthorized: Missing bearer`, complete codex auth/login before rerun.

## Documents

- Windows guide: `win/GLOBAL_BOOTSTRAP_TEAM_GUIDE.md`
- Windows teammate quickstart: `win/TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md`
- WSL guide: `wsl/GLOBAL_BOOTSTRAP_TEAM_GUIDE.md`
- WSL teammate quickstart: `wsl/TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md`
- Feature comparison (EN): `docs/FEATURE_COMPARISON.md`
- Feature comparison (ZH): `docs/FEATURE_COMPARISON.zh-CN.md`
- Full feature manual (EN): `docs/FEATURE_MANUAL.md`
- Full feature manual (ZH): `docs/FEATURE_MANUAL.zh-CN.md`
- Publishing model and open-source boundary: `docs/PUBLISHING_MODEL.md`
- Publishing model and open-source boundary (ZH): `docs/PUBLISHING_MODEL.zh-CN.md`
- Release checklist: `docs/RELEASE_CHECKLIST.md`
- Portability checks: `docs/PORTABILITY_CHECKS.md`

## Security

- Never commit real tokens or `.env` secrets.
- Keep only placeholders in docs/examples (for example `ghp_xxx`).
- See `SECURITY.md` for reporting process.

## License

- This repository: MIT (`LICENSE`)
- Third-party components and submodules: see `THIRD_PARTY_NOTICES.md`
