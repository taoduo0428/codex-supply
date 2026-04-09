#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/common.sh"

workspace_path=""
smoke_timeout_seconds=300
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-path) workspace_path="$2"; shift 2 ;;
    --smoke-timeout-seconds) smoke_timeout_seconds="$2"; shift 2 ;;
    *) printf '[ERROR] Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

workspace_path="$(resolve_workspace_path "$workspace_path")"
ensure_dir "$AUTOMATION_HOME/logs"
log_path="$AUTOMATION_HOME/logs/daily-smoke-$(date +%Y%m%d-%H%M%S).log"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$log_path"
}

log 'Automation daily smoke started.'
log "WorkspacePath used for runtime validation: $workspace_path"
log 'Step 1/2: validate global runtime'
if "$SCRIPT_DIR/validate_global_runtime.sh" --expected-workspace-path "$workspace_path" 2>&1 | tee -a "$log_path"; then
  log 'validate_global_runtime exit code: 0'
else
  code=$?
  log "validate_global_runtime exit code: $code"
  log 'Automation failed at runtime validation.'
  exit "$code"
fi

log 'Step 2/2: run smoke prompts'
if "$SCRIPT_DIR/run_smoke_prompts.sh" --workspace-path "$workspace_path" --timeout-seconds "$smoke_timeout_seconds" --fail-on-any-failure 2>&1 | tee -a "$log_path"; then
  log 'run_smoke_prompts exit code: 0'
  log 'Automation daily smoke finished successfully.'
  exit 0
else
  code=$?
  log "run_smoke_prompts exit code: $code"
  log 'Automation finished with failures.'
  exit "$code"
fi
