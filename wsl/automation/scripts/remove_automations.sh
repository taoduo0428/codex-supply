#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT
(current_cron="$(crontab -l 2>/dev/null || true)"; printf '%s\n' "$current_cron" | grep -Ev 'Codex-Auto-Daily-Smoke|Codex-Auto-Git-Review|Codex-Auto-Nightly-Memory|Codex-Proactive-Heartbeat' > "$tmp_file" || true)
crontab "$tmp_file"
printf 'Automation cleanup complete.\n'
