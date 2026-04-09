#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/common.sh"

workspace_path=""
git_repo_path=""
daily_smoke_time='09:00'
git_review_interval_hours=4
git_review_timeout_seconds=180
nightly_memory_time='01:30'
proactive_interval_hours=2
skip_daily_smoke=0
skip_git_review=0
skip_nightly_memory=0
skip_proactive=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-path) workspace_path="$2"; shift 2 ;;
    --git-repo-path) git_repo_path="$2"; shift 2 ;;
    --daily-smoke-time) daily_smoke_time="$2"; shift 2 ;;
    --git-review-interval-hours) git_review_interval_hours="$2"; shift 2 ;;
    --git-review-timeout-seconds) git_review_timeout_seconds="$2"; shift 2 ;;
    --nightly-memory-time) nightly_memory_time="$2"; shift 2 ;;
    --proactive-interval-hours) proactive_interval_hours="$2"; shift 2 ;;
    --skip-daily-smoke) skip_daily_smoke=1; shift ;;
    --skip-git-review) skip_git_review=1; shift ;;
    --skip-nightly-memory) skip_nightly_memory=1; shift ;;
    --skip-proactive) skip_proactive=1; shift ;;
    *) printf '[ERROR] Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
ensure_dir "$AUTOMATION_HOME/logs"
ensure_dir "$AUTOMATION_HOME/reports"
ensure_dir "$AUTOMATION_HOME/tmp_smoke/runs"
workspace_path="$(resolve_workspace_path "$workspace_path")"
if test_git_repo "$git_repo_path"; then
  "$SCRIPT_DIR/set_active_repo.sh" --repo-path "$git_repo_path" >/dev/null
elif test_git_repo "$workspace_path"; then
  "$SCRIPT_DIR/set_active_repo.sh" --repo-path "$workspace_path" >/dev/null
fi

crontab_current="$(crontab -l 2>/dev/null || true)"
tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT
printf '%s\n' "$crontab_current" | grep -Ev 'Codex-Auto-Daily-Smoke|Codex-Auto-Git-Review|Codex-Auto-Nightly-Memory|Codex-Proactive-Heartbeat' > "$tmp_file" || true
if [[ "$skip_daily_smoke" -eq 0 ]]; then
  hour="${daily_smoke_time%:*}"
  minute="${daily_smoke_time#*:}"
  printf '%s %s * * * bash %q --workspace-path %q >> %q 2>&1 # Codex-Auto-Daily-Smoke\n' "$minute" "$hour" "$SCRIPT_DIR/automation_daily_smoke.sh" "$workspace_path" "$AUTOMATION_HOME/logs/cron-daily-smoke.log" >> "$tmp_file"
fi
if [[ "$skip_git_review" -eq 0 ]]; then
  printf '5 */%s * * * bash %q --workspace-path %q --timeout-seconds %q >> %q 2>&1 # Codex-Auto-Git-Review\n' "$git_review_interval_hours" "$SCRIPT_DIR/automation_git_review.sh" "$workspace_path" "$git_review_timeout_seconds" "$AUTOMATION_HOME/logs/cron-git-review.log" >> "$tmp_file"
fi
if [[ "$skip_nightly_memory" -eq 0 ]]; then
  night_hour="${nightly_memory_time%:*}"
  night_minute="${nightly_memory_time#*:}"
  printf '%s %s * * * bash %q >> %q 2>&1 # Codex-Auto-Nightly-Memory\n' "$night_minute" "$night_hour" "$SCRIPT_DIR/automation_self_improve_nightly.sh" "$AUTOMATION_HOME/logs/cron-nightly-memory.log" >> "$tmp_file"
fi
if [[ "$skip_proactive" -eq 0 ]]; then
  printf '0 */%s * * * bash %q >> %q 2>&1 # Codex-Proactive-Heartbeat\n' "$proactive_interval_hours" "$SCRIPT_DIR/automation_proactive_heartbeat.sh" "$AUTOMATION_HOME/logs/cron-proactive-heartbeat.log" >> "$tmp_file"
fi
crontab "$tmp_file"
printf 'Automations registered.\n'
printf 'WorkspacePath: %s\n' "$workspace_path"
printf 'ActiveRepoFilePath: %s\n' "$ACTIVE_REPO_FILE"
crontab -l | grep 'Codex-' || true
