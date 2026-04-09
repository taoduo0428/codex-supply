# Global Automation Runtime (WSL)

This directory hosts user-level automation scripts for Codex in WSL/Linux.

## Layout
- `scripts/common.sh`
- `scripts/automation_daily_smoke.sh`
- `scripts/automation_git_review.sh`
- `scripts/automation_proactive_heartbeat.sh`
- `scripts/automation_self_improve_nightly.sh`
- `scripts/run_smoke_prompts.sh`
- `scripts/validate_global_runtime.sh`
- `scripts/setup_automations.sh`
- `scripts/remove_automations.sh`
- `scripts/set_active_repo.sh`
- `scripts/setup_proactive_heartbeat_task.sh`

## Active repo pointer
- `$HOME/.agents/active-repo.txt`

## Cron job tags
- `Codex-Auto-Daily-Smoke`
- `Codex-Auto-Git-Review`
- `Codex-Auto-Nightly-Memory`
- `Codex-Proactive-Heartbeat`

## Environment variables (recommended)

`scripts/common.sh` auto-loads optional env files:

- `$HOME/.agents/automation/.env`
- `$HOME/.codex/.env`

Typical credentials:

```bash
GITHUB_TOKEN=ghp_xxx
# or
GITHUB_PAT=ghp_xxx
```

You can copy and edit:

```bash
cp "$HOME/.agents/automation/.env.example" "$HOME/.agents/automation/.env"
chmod 600 "$HOME/.agents/automation/.env"
```

## Smoke stability notes

- `run_smoke_prompts.sh` supports retries for timeout/empty-output cases.
- Non-`integration-runtime` cases run with MCP disabled by default to reduce OAuth/keyring noise.
- If `--timeout-seconds` is too small, `workspace-core` and `integration-runtime` are auto-raised to a minimum of `90s`.
- Codex binary is auto-resolved to a runnable binary (falls back to VS Code extension codex when PATH codex is broken).

## OAuth keyring in WSL

If you see warnings like `org.freedesktop.secrets ... ServiceUnknown`, run:

```bash
bash "$HOME/.agents/automation/scripts/setup_wsl_secret_service.sh"
source ~/.bashrc
```

The script installs/starts Secret Service (`gnome-keyring`) and writes shell startup hooks.
If package installation needs privilege, it prints the exact `sudo apt-get ...` command.

Useful commands:

```bash
bash "$HOME/.agents/automation/scripts/validate_global_runtime.sh" \
  --expected-workspace-path "/mnt/c/Users/<YOUR_USER>/Documents/<YOUR_WORKSPACE>"

bash "$HOME/.agents/automation/scripts/run_smoke_prompts.sh" \
  --workspace-path "/mnt/c/Users/<YOUR_USER>/Documents/<YOUR_WORKSPACE>" \
  --retry-attempts 2 \
  --timeout-seconds 120
```
