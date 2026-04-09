#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
interval_hours=2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval-hours) interval_hours="$2"; shift 2 ;;
    *) printf '[ERROR] Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
if [[ "$interval_hours" -lt 1 ]]; then
  printf '[ERROR] interval-hours must be >= 1\n' >&2
  exit 2
fi
tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT
current_cron="$(crontab -l 2>/dev/null || true)"
printf '%s\n' "$current_cron" | grep -Ev 'Codex-Proactive-Heartbeat' > "$tmp_file" || true
printf '0 */%s * * * bash %q >> %q 2>&1 # Codex-Proactive-Heartbeat\n' "$interval_hours" "$SCRIPT_DIR/automation_proactive_heartbeat.sh" "$HOME/.agents/automation/logs/cron-proactive-heartbeat.log" >> "$tmp_file"
crontab "$tmp_file"
printf 'Proactive heartbeat cron registered.\n'
