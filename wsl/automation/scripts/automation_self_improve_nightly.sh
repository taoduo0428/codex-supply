#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/common.sh"

python_bin="$(require_global_python)"
package_dir="$CODEX_HOME/self-improving-for-codex"
pipeline_script="$package_dir/scripts/run_night_memory_pipeline.py"
memory_dir="$CODEX_HOME/memories"
status_dir="$CODEX_HOME/runtime/night-memory-pipeline"
lock_dir="$CODEX_HOME/runtime/locks"
log_dir="$AUTOMATION_HOME/logs"
status_path="$status_dir/last_run.json"
log_path="$log_dir/self_improve_nightly.log"

[[ -f "$pipeline_script" ]] || { printf '[ERROR] Missing pipeline script: %s\n' "$pipeline_script" >&2; exit 1; }
[[ -d "$memory_dir" ]] || { printf '[ERROR] Missing memory directory: %s\n' "$memory_dir" >&2; exit 1; }
ensure_dir "$log_dir"
ensure_dir "$status_dir"
ensure_dir "$lock_dir"

printf '[%s] Starting self-improving nightly pipeline.\n' "$(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$log_path" >/dev/null
if "$python_bin" "$pipeline_script" --apply --main-memory-dir "$memory_dir" --bridge-memory-dir "$memory_dir" --lock-dir "$lock_dir" --status-path "$status_path" 2>&1 | tee -a "$log_path" >/dev/null; then
  code=0
else
  code=$?
fi
printf '[%s] Finished with exit code: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$code" | tee -a "$log_path" >/dev/null
exit "$code"
