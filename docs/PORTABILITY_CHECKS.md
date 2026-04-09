# Portability Checks

## Required placeholders

Use placeholders in all docs/examples instead of personal paths:

- `$HOME/.agents/...`
- `$HOME/.codex/...`
- `/mnt/c/Users/<YOUR_USER>/...`
- `C:\Users\<YOUR_USER>\...`

## Forbidden machine-specific values

Do not publish these in docs or scripts:

- `/home/<REAL_USER>`
- `/mnt/c/Users/<REAL_USER>`
- `C:\Users\<REAL_USER>`
- real tokens (`github_pat_*`, `ghp_*`, `OPENAI_API_KEY=*`)

## Bundle contract

This repository assumes:

- Windows script entry: `win/bootstrap_fresh_global_full.ps1`
- WSL script entry: `wsl/bootstrap_fresh_global_full.sh`
- Shared assets root: `common/claude-code-main`
- Optional modules root: `external/*`
- Missing optional module folders are auto-handled by submodule init attempt unless skip-submodule-init is explicitly enabled
- Public release boundary: publish `GitHub上线` as repository root; do not publish local `源码工程` workspace

If you change these paths, update both Win and WSL docs in the same PR.
