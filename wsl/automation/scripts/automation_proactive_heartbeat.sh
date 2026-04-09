#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/common.sh"

max_changed_files_for_warning=40
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-changed-files-for-warning) max_changed_files_for_warning="$2"; shift 2 ;;
    *) printf '[ERROR] Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

runtime_dir="$CODEX_HOME/runtime/proactive"
status_dir="$CODEX_HOME/runtime/night-memory-pipeline"
log_dir="$AUTOMATION_HOME/logs"
heartbeat_path="$runtime_dir/heartbeat-latest.json"
context_path="$runtime_dir/context-recovery-latest.md"
log_path="$log_dir/proactive_heartbeat.log"
night_status_path="$status_dir/last_run.json"
ensure_dir "$runtime_dir"
ensure_dir "$log_dir"
repo_path="$(resolve_repo_path '' || true)"
branch=''
last_commit=''
changed_count=0
changed_preview='[]'
if [[ -n "$repo_path" ]]; then
  branch="$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null | head -n1 || true)"
  last_commit="$(git -C "$repo_path" log -1 --pretty=format:'%h %s (%cr)' 2>/dev/null | head -n1 || true)"
  changed_count="$(git -C "$repo_path" status --short 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l)"
  changed_preview="$(git -C "$repo_path" status --short 2>/dev/null | sed '/^[[:space:]]*$/d' | head -n 20 | python3 -c 'import json,sys; print(json.dumps([line.rstrip("\n") for line in sys.stdin], ensure_ascii=False))')"
fi
cron_dump="$(crontab -l 2>/dev/null || true)"
has_daily=false
has_git_review=false
has_nightly=false
has_proactive=false
printf '%s' "$cron_dump" | grep -q 'Codex-Auto-Daily-Smoke' && has_daily=true || true
printf '%s' "$cron_dump" | grep -q 'Codex-Auto-Git-Review' && has_git_review=true || true
printf '%s' "$cron_dump" | grep -q 'Codex-Auto-Nightly-Memory' && has_nightly=true || true
printf '%s' "$cron_dump" | grep -q 'Codex-Proactive-Heartbeat' && has_proactive=true || true
night_summary='{}'
night_overall=''
night_finished=''
night_exists=false
if [[ -f "$night_status_path" ]]; then
  night_exists=true
  night_summary="$(python3 - "$night_status_path" <<'PY'
import json,sys
try:
    data=json.loads(open(sys.argv[1],encoding='utf-8').read())
except Exception:
    print('{}')
else:
    print(json.dumps(data, ensure_ascii=False))
PY
)"
  night_overall="$(python3 - "$night_status_path" <<'PY'
import json,sys
try:
    data=json.loads(open(sys.argv[1],encoding='utf-8').read())
except Exception:
    print('')
else:
    print(str(data.get('overall_status','') or ''))
PY
)"
  night_finished="$(python3 - "$night_status_path" <<'PY'
import json,sys
try:
    data=json.loads(open(sys.argv[1],encoding='utf-8').read())
except Exception:
    print('')
else:
    print(str(data.get('finished_at','') or ''))
PY
)"
fi
blockers=()
risk_signals=()
next_steps=()
if [[ -z "$repo_path" ]]; then
  blockers+=(NO_ACTIVE_GIT_REPO)
else
  next_steps+=('Resume from current repo branch and latest commit context before new edits.')
  if [[ "$changed_count" -gt 0 ]]; then
    next_steps+=('Review staged and unstaged changes and decide the next atomic commit.')
  fi
fi
if [[ "$changed_count" -gt "$max_changed_files_for_warning" ]]; then
  risk_signals+=(LARGE_UNCOMMITTED_CHANGESET)
fi
if [[ -n "$night_overall" && "$night_overall" != success ]]; then
  blockers+=(NIGHT_MEMORY_PIPELINE_NOT_SUCCESS)
fi
[[ "$has_daily" == true ]] || risk_signals+=(MISSING_CRON:Codex-Auto-Daily-Smoke)
[[ "$has_git_review" == true ]] || risk_signals+=(MISSING_CRON:Codex-Auto-Git-Review)
[[ "$has_nightly" == true ]] || risk_signals+=(MISSING_CRON:Codex-Auto-Nightly-Memory)
[[ "$has_proactive" == true ]] || risk_signals+=(MISSING_CRON:Codex-Proactive-Heartbeat)
if [[ "${#next_steps[@]}" -eq 0 ]]; then
  next_steps+=('No critical blocker detected; continue normal execution.')
fi
array_to_json() {
  python3 - <<'PY' "$@"
import json
import sys
print(json.dumps(sys.argv[1:], ensure_ascii=False))
PY
}

blockers_json="$(array_to_json "${blockers[@]}")"
risk_signals_json="$(array_to_json "${risk_signals[@]}")"
next_steps_json="$(array_to_json "${next_steps[@]}")"

python3 - "$heartbeat_path" "$repo_path" "$branch" "$last_commit" "$changed_count" "$changed_preview" "$night_status_path" "$night_exists" "$night_overall" "$night_finished" "$has_daily" "$has_git_review" "$has_nightly" "$has_proactive" "$blockers_json" "$risk_signals_json" "$next_steps_json" <<'PY'
import json
import sys
from datetime import datetime
path = sys.argv[1]
repo_path, branch, last_commit = sys.argv[2:5]
changed_count = int(sys.argv[5])
changed_preview = json.loads(sys.argv[6])
night_status_path = sys.argv[7]
night_exists = sys.argv[8] == 'true'
night_overall, night_finished = sys.argv[9:11]
has_daily, has_git_review, has_nightly, has_proactive = [v == 'true' for v in sys.argv[11:15]]
blockers = json.loads(sys.argv[15])
risk_signals = json.loads(sys.argv[16])
next_steps = json.loads(sys.argv[17])
payload = {
    'generated_at': datetime.now().astimezone().isoformat(timespec='seconds'),
    'repo': {
        'path': repo_path,
        'branch': branch,
        'last_commit': last_commit,
        'changed_count': changed_count,
        'changed_preview': changed_preview,
    },
    'night_memory': {
        'status_file': night_status_path,
        'exists': night_exists,
        'overall_status': night_overall,
        'finished_at': night_finished,
    },
    'tasks': [
        {'task_name': 'Codex-Auto-Daily-Smoke', 'exists': has_daily},
        {'task_name': 'Codex-Auto-Git-Review', 'exists': has_git_review},
        {'task_name': 'Codex-Auto-Nightly-Memory', 'exists': has_nightly},
        {'task_name': 'Codex-Proactive-Heartbeat', 'exists': has_proactive},
    ],
    'blockers': blockers,
    'risk_signals': risk_signals,
    'next_steps': next_steps,
}
with open(path, 'w', encoding='utf-8') as fh:
    json.dump(payload, fh, ensure_ascii=False, indent=2)
    fh.write('\n')
PY
{
  printf '# Proactive Context Recovery Snapshot\n\n'
  printf -- '- Generated: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf -- '- Repo: %s\n' "${repo_path:-'(none)'}"
  printf -- '- Branch: %s\n' "${branch:-'(unknown)'}"
  printf -- '- Last Commit: %s\n' "${last_commit:-'(unknown)'}"
  printf -- '- Changed Files: %s\n\n' "$changed_count"
  printf '## Blockers\n'
  if [[ "${#blockers[@]}" -gt 0 ]]; then printf -- '- %s\n' "${blockers[@]}"; else printf -- '- none\n'; fi
  printf '\n## Risk Signals\n'
  if [[ "${#risk_signals[@]}" -gt 0 ]]; then printf -- '- %s\n' "${risk_signals[@]}"; else printf -- '- none\n'; fi
  printf '\n## Next Steps\n'
  i=1
  for step in "${next_steps[@]}"; do printf '%d. %s\n' "$i" "$step"; i=$((i+1)); done
  printf '\n## Changed Files Preview\n'
  if [[ -n "$repo_path" && "$changed_count" -gt 0 ]]; then
    printf '```text\n'
    git -C "$repo_path" status --short 2>/dev/null | sed '/^[[:space:]]*$/d' | head -n 20
    printf '```\n'
  else
    printf -- '- clean working tree or no active repo\n'
  fi
} > "$context_path"
printf '[%s] proactive-heartbeat ok | repo=%s | changed=%s | blockers=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${repo_path:-'(none)'}" "$changed_count" "${#blockers[@]}" >> "$log_path"
printf 'Heartbeat: %s\n' "$heartbeat_path"
printf 'Context: %s\n' "$context_path"
