#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/common.sh"

workspace_path=""
out_dir="$AUTOMATION_HOME/tmp_smoke/runs"
timeout_seconds=300
disable_mcp=0
fail_on_any_failure=0
only_csv=""
retry_attempts=2
retry_backoff_seconds=5
codex_bin_override=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-path) workspace_path="$2"; shift 2 ;;
    --out-dir) out_dir="$2"; shift 2 ;;
    --only) only_csv="$2"; shift 2 ;;
    --timeout-seconds) timeout_seconds="$2"; shift 2 ;;
    --disable-mcp) disable_mcp=1; shift ;;
    --retry-attempts) retry_attempts="$2"; shift 2 ;;
    --retry-backoff-seconds) retry_backoff_seconds="$2"; shift 2 ;;
    --codex-bin) codex_bin_override="$2"; shift 2 ;;
    --fail-on-any-failure) fail_on_any_failure=1; shift ;;
    *) printf '[ERROR] Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

workspace_path="$(resolve_workspace_path "$workspace_path")"
ensure_dir "$out_dir"
if [[ -n "$codex_bin_override" ]]; then
  CODEX_BIN="$codex_bin_override"
fi
require_codex_bin
if [[ "$retry_attempts" -lt 1 ]]; then
  retry_attempts=1
fi

declare -a ids=(workspace-core git-review agent-orchestration integration-runtime personal-productivity)
declare -A prompt_map keyword_map min_hits_map
prompt_map[workspace-core]='Scan this repository, summarize current workspace status, and list the top risks before coding. Do not modify files.'
prompt_map[git-review]='Summarize the recent changes in this repo and prepare a clean commit plan. Do not modify files.'
prompt_map[agent-orchestration]='Break this feature delivery into a planner/executor workflow with milestones and verification gates. Do not modify files.'
prompt_map[integration-runtime]='Inspect runtime integrations and list MCP-backed capabilities available in this environment. Do not modify files.'
prompt_map[personal-productivity]='Review this implementation approach, identify likely failure points, and give a lightweight verify/debug loop. Do not modify files.'
keyword_map[workspace-core]='workspace,status,risk,repository,context'
keyword_map[git-review]='commit,changes,diff,plan,review'
keyword_map[agent-orchestration]='planner,executor,milestone,verification,phase,gate'
keyword_map[integration-runtime]='mcp,playwright,filesystem,fetch,git,github,integration'
keyword_map[personal-productivity]='failure,verify,debug,loop,risk,check'
min_hits_map[workspace-core]=2
min_hits_map[git-review]=2
min_hits_map[agent-orchestration]=3
min_hits_map[integration-runtime]=4
min_hits_map[personal-productivity]=3

selected=("${ids[@]}")
if [[ -n "$only_csv" ]]; then
  IFS=',' read -r -a wanted <<< "$only_csv"
  selected=()
  for item in "${wanted[@]}"; do
    item="${item// /}"
    [[ -n "$item" ]] && [[ -n "${prompt_map[$item]:-}" ]] && selected+=("$item")
  done
  [[ "${#selected[@]}" -gt 0 ]] || { printf '[ERROR] No valid case matched --only\n' >&2; exit 2; }
fi

printf 'Running smoke prompts with codex exec...\n'
printf 'Workspace: %s\n' "$workspace_path"
printf 'Output: %s\n' "$out_dir"
printf 'Cases: %s\n' "${selected[*]}"
printf 'TimeoutSeconds per case: %s\n' "$timeout_seconds"
printf 'DisableMcp: %s\n' "$disable_mcp"
printf 'RetryAttempts: %s\n' "$retry_attempts"
printf 'RetryBackoffSeconds: %s\n' "$retry_backoff_seconds"
printf 'Codex binary: %s\n' "$CODEX_BIN"

results_tsv="$(mktemp)"
trap 'rm -f "$results_tsv"' EXIT

for id in "${selected[@]}"; do
  stdout_path="$out_dir/$id.stdout.log"
  stderr_path="$out_dir/$id.stderr.log"
  combined_path="$out_dir/$id.combined.log"
  last_path="$out_dir/$id.last.txt"
  rm -f "$stdout_path" "$stderr_path" "$combined_path" "$last_path" || true
  : > "$stdout_path"
  : > "$stderr_path"
  : > "$combined_path"

  printf '\n=== Running: %s ===\n' "$id"
  start_epoch="$(date +%s)"
  prompt="${prompt_map[$id]}"

  exit_code=0
  timed_out=false
  hits=0
  min_hits="${min_hits_map[$id]}"
  has_output=false
  status='FAIL'
  attempts_used=0
  case_timeout_seconds="$timeout_seconds"
  if [[ "$case_timeout_seconds" -lt 90 ]] && [[ "$id" == "workspace-core" || "$id" == "integration-runtime" ]]; then
    case_timeout_seconds=90
  fi

  for ((attempt=1; attempt<=retry_attempts; attempt++)); do
    attempts_used="$attempt"
    attempt_stdout="$out_dir/$id.stdout.attempt$attempt.log"
    attempt_stderr="$out_dir/$id.stderr.attempt$attempt.log"
    rm -f "$attempt_stdout" "$attempt_stderr" || true

    # Non-integration cases run with MCP disabled by default to reduce OAuth/keyring noise.
    effective_disable_mcp="$disable_mcp"
    if [[ "$effective_disable_mcp" -eq 0 && "$id" != "integration-runtime" ]]; then
      effective_disable_mcp=1
    fi

    cmd=("$CODEX_BIN" exec --ephemeral -c model_reasoning_effort=low -s read-only -o "$last_path" --cd "$workspace_path")
    if [[ "$effective_disable_mcp" -eq 1 ]]; then
      cmd+=(-c 'mcp_servers={}')
    fi
    cmd+=("$prompt")

    attempt_exit_code=0
    attempt_timed_out=false
    if command -v timeout >/dev/null 2>&1; then
      if timeout --preserve-status "${case_timeout_seconds}s" "${cmd[@]}" >"$attempt_stdout" 2>"$attempt_stderr"; then
        attempt_exit_code=0
      else
        attempt_exit_code=$?
        [[ "$attempt_exit_code" -eq 124 || "$attempt_exit_code" -eq 137 || "$attempt_exit_code" -eq 143 ]] && attempt_timed_out=true
      fi
    else
      if "${cmd[@]}" >"$attempt_stdout" 2>"$attempt_stderr"; then
        attempt_exit_code=0
      else
        attempt_exit_code=$?
      fi
    fi

    {
      printf '===== Attempt %s =====\n' "$attempt"
      cat "$attempt_stdout" 2>/dev/null || true
      printf '\n'
    } >> "$stdout_path"
    {
      printf '===== Attempt %s =====\n' "$attempt"
      cat "$attempt_stderr" 2>/dev/null || true
      printf '\n'
    } >> "$stderr_path"
    {
      printf '===== Attempt %s / STDOUT =====\n' "$attempt"
      cat "$attempt_stdout" 2>/dev/null || true
      printf '\n===== Attempt %s / STDERR =====\n' "$attempt"
      cat "$attempt_stderr" 2>/dev/null || true
      printf '\n'
    } >> "$combined_path"

    last_message=''
    [[ -f "$last_path" ]] && last_message="$(cat "$last_path")"
    if [[ -z "${last_message//[[:space:]]/}" ]] && [[ -s "$attempt_stdout" ]]; then
      # Some codex runs may write the final text to stdout but leave -o output empty.
      # Persist fallback content to keep artifacts and keyword checks stable.
      last_message="$(cat "$attempt_stdout")"
      printf '%s\n' "$last_message" >"$last_path"
    fi
    hits="$(python3 - "$last_path" "${keyword_map[$id]}" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
keywords = [item.strip().lower() for item in sys.argv[2].split(',') if item.strip()]
text = path.read_text(encoding='utf-8', errors='replace').lower() if path.exists() else ''
print(sum(1 for kw in keywords if kw in text))
PY
)"
    has_output=false
    [[ -n "${last_message//[[:space:]]/}" ]] && has_output=true
    status='FAIL'
    if [[ "$has_output" == true && "$hits" -ge "$min_hits" ]]; then
      status='PASS'
    fi

    exit_code="$attempt_exit_code"
    timed_out="$attempt_timed_out"

    if [[ "$status" == PASS ]]; then
      break
    fi

    should_retry=0
    if [[ "$attempt" -lt "$retry_attempts" ]]; then
      if [[ "$attempt_timed_out" == true || "$has_output" == false ]]; then
        should_retry=1
      fi
    fi
    if [[ "$should_retry" -eq 1 ]]; then
      printf 'Retrying case=%s attempt=%s/%s after %ss (exit=%s timed_out=%s has_output=%s hits=%s/%s)\n' \
        "$id" "$attempt" "$retry_attempts" "$retry_backoff_seconds" "$attempt_exit_code" "$attempt_timed_out" "$has_output" "$hits" "$min_hits"
      sleep "$retry_backoff_seconds"
    else
      break
    fi
  done

  end_epoch="$(date +%s)"
  duration=$((end_epoch - start_epoch))

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$id" "$timed_out" "$exit_code" "$hits" "$min_hits" "$has_output" "$duration" "$attempts_used" "$status" >> "$results_tsv"
done

report_path="$AUTOMATION_HOME/SMOKE_TEST_RESULTS.md"
generated_at="$(date '+%Y-%m-%d %H:%M:%S')"
{
  printf '# SMOKE_TEST_RESULTS\n\n'
  printf -- '- Generated at: %s\n' "$generated_at"
  printf -- '- Workspace: %s\n' "$workspace_path"
  printf -- '- Runner: %s\n' 'scripts/run_smoke_prompts.sh'
  printf -- '- TimeoutSeconds: %s\n' "$timeout_seconds"
  printf -- '- DisableMcp: %s\n\n' "$disable_mcp"
  printf '| Case | Timeout | Exit Code | Hits/Min | Has Output | Attempts | Status |\n'
  printf '|---|---|---:|---:|---|---:|---|\n'
  failed_cases=()
  while IFS=$'\t' read -r id timed_out exit_code hits min_hits has_output duration attempts_used status; do
    printf '| %s | %s | %s | %s/%s | %s | %s | %s |\n' "$id" "$timed_out" "$exit_code" "$hits" "$min_hits" "$has_output" "$attempts_used" "$status"
    [[ "$status" == PASS ]] || failed_cases+=("$id")
  done < "$results_tsv"
  printf '\n## Artifacts\n'
  while IFS=$'\t' read -r id timed_out exit_code hits min_hits has_output duration attempts_used status; do
    printf -- '- %s: output=%s, stdout=%s, stderr=%s, combined=%s\n' "$id" "$out_dir/$id.last.txt" "$out_dir/$id.stdout.log" "$out_dir/$id.stderr.log" "$out_dir/$id.combined.log"
  done < "$results_tsv"
  printf '\n'
  if [[ "${#failed_cases[@]}" -eq 0 ]]; then
    printf 'All selected smoke prompt runs passed.\n'
  else
    printf 'Failed cases: %s\n' "${failed_cases[*]}"
  fi
} > "$report_path"

printf '\nSmoke results written to: %s\n' "$report_path"
failed_count="$(awk -F '\t' '$9 != "PASS" {c++} END {print c+0}' "$results_tsv")"
if [[ "$failed_count" -gt 0 ]]; then
  printf 'Failed cases: %s\n' "$(awk -F '\t' '$9 != "PASS" {print $1}' "$results_tsv" | paste -sd ', ' -)"
  [[ "$fail_on_any_failure" -eq 1 ]] && exit 1
fi
