#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/common.sh"

workspace_path=""
output_root="$AUTOMATION_HOME"
timeout_seconds=420
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-path) workspace_path="$2"; shift 2 ;;
    --active-repo-file) ACTIVE_REPO_FILE="$2"; shift 2 ;;
    --output-root-path) output_root="$2"; shift 2 ;;
    --timeout-seconds) timeout_seconds="$2"; shift 2 ;;
    *) printf '[ERROR] Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

ensure_dir "$output_root/logs"
ensure_dir "$output_root/reports"
timestamp="$(date +%Y%m%d-%H%M%S)"
stdout_path="$output_root/logs/git-review-$timestamp.stdout.log"
stderr_path="$output_root/logs/git-review-$timestamp.stderr.log"
report_path="$output_root/reports/git-review-$timestamp.md"
latest_report_path="$output_root/reports/git-review-latest.md"
meta_path="$output_root/reports/git-review-$timestamp.meta.txt"
repo_path="$(resolve_repo_path "$workspace_path" || true)"

meta() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$meta_path"
}

git_out() {
  git -C "$repo_path" "$@" 2>/dev/null || true
}

write_fallback_report() {
  local reason="$1"
  local generated_at branch status_short staged_files unstaged_files recent_commits total_changed staged_count unstaged_count
  generated_at="$(date '+%Y-%m-%d %H:%M:%S')"
  branch="$(git_out rev-parse --abbrev-ref HEAD | head -n1)"
  [[ -n "$branch" ]] || branch='(unknown)'
  status_short="$(git_out status --short)"
  staged_files="$(git_out diff --cached --name-only)"
  unstaged_files="$(git_out diff --name-only)"
  recent_commits="$(git_out log -5 --pretty=format:'- %h %s (%cr)')"
  total_changed="$(printf '%s\n' "$status_short" | sed '/^[[:space:]]*$/d' | wc -l)"
  staged_count="$(printf '%s\n' "$staged_files" | sed '/^[[:space:]]*$/d' | wc -l)"
  unstaged_count="$(printf '%s\n' "$unstaged_files" | sed '/^[[:space:]]*$/d' | wc -l)"
  {
    printf '# Git Review Report (Fallback)\n\n'
    printf -- '- Generated: %s\n' "$generated_at"
    printf -- '- Repo: %s\n' "$repo_path"
    printf -- '- Branch: %s\n' "$branch"
    printf -- '- Reason: %s\n\n' "$reason"
    printf '## Summary\n'
    printf -- '- Changed entries: %s\n' "$total_changed"
    printf -- '- Staged files: %s\n' "$staged_count"
    printf -- '- Unstaged files: %s\n\n' "$unstaged_count"
    printf '## Top Risks\n'
    if [[ "$total_changed" -gt 20 ]]; then printf -- '- Many files changed; split commits to reduce review risk.\n'; fi
    if [[ "$staged_count" -eq 0 && "$unstaged_count" -gt 0 ]]; then printf -- '- No staged changes yet; stage by feature before commit.\n'; fi
    if [[ "$staged_count" -gt 0 && "$unstaged_count" -gt 0 ]]; then printf -- '- Mixed staged/unstaged state; verify commit boundary.\n'; fi
    if [[ "$total_changed" -eq 0 ]]; then printf -- '- No uncommitted changes; focus on latest commit quality.\n'; fi
    if [[ "$total_changed" -le 20 && ! ( "$staged_count" -eq 0 && "$unstaged_count" -gt 0 ) && ! ( "$staged_count" -gt 0 && "$unstaged_count" -gt 0 ) && ! ( "$total_changed" -eq 0 ) ]]; then
      printf -- '- No high-risk signal detected from git state.\n'
    fi
    printf '\n## Commit Plan\n'
    printf -- '- 1. Split changes into small, reversible commits.\n'
    printf -- '- 2. Run minimum checks (tests/lint/type-check) before commit.\n'
    printf -- '- 3. Use clear commit message format: <type>(scope): summary.\n'
    printf -- '- 4. Add short impact notes for reviewer context.\n\n'
    printf '## Commit Quality Checklist\n'
    printf -- '- [ ] Local checks passed (minimum critical path)\n'
    printf -- '- [ ] No temporary debug code/logs left\n'
    printf -- '- [ ] Commit message is clear and scoped\n'
    printf -- '- [ ] Docs/examples updated when config changed\n\n'
    printf '## Recent Commits\n'
    if [[ -n "${recent_commits//[[:space:]]/}" ]]; then
      printf '%s\n' "$recent_commits"
    else
      printf -- '- (no commits found)\n'
    fi
    printf '\n## Changed Files (status --short)\n'
    if [[ -n "${status_short//[[:space:]]/}" ]]; then
      printf '```text\n%s\n```\n' "$status_short"
    else
      printf -- '- (clean working tree)\n'
    fi
  } > "$report_path"
}

meta "Automation git review started."
meta "WorkspacePath: ${workspace_path:-}"
meta "ActiveRepoFilePath: $ACTIVE_REPO_FILE"
meta "OutputRootPath: $output_root"
if [[ -z "$repo_path" ]]; then
  meta 'Skipped: no valid git repo from workspace or active-repo fallback.'
  exit 0
fi
meta "Resolved target repo: $repo_path"
status_short="$(git_out status --short)"
last_commit="$(git_out log -1 --pretty=format:'%h %s (%cr)' | head -n1)"
if [[ -z "${status_short//[[:space:]]/}" && -z "$last_commit" ]]; then
  meta 'No git information available. Writing fallback report.'
  write_fallback_report 'no_git_information_available'
  cp "$report_path" "$latest_report_path"
  printf 'Report: %s\n' "$report_path"
  printf 'Latest: %s\n' "$latest_report_path"
  exit 0
fi
prompt=$'Review this repository state and produce a concise git review report:\n- summarize current changes and/or latest commit context\n- identify top risks or regressions\n- propose a clean commit plan\n- include a short checklist for next commit quality\nDo not modify any files.'
if [[ -n "$CODEX_BIN" && -x "$CODEX_BIN" ]]; then
  meta "Codex binary resolved: $CODEX_BIN"
  if command -v timeout >/dev/null 2>&1; then
    if timeout --preserve-status "$timeout_seconds"s "$CODEX_BIN" exec -c model_reasoning_effort=low -s read-only -o "$report_path" --cd "$repo_path" "$prompt" >"$stdout_path" 2>"$stderr_path"; then
      meta 'Codex git review completed successfully.'
    else
      code=$?
      meta "Codex git review failed with exit code: $code"
      write_fallback_report "codex_exit_code=$code"
    fi
  else
    if "$CODEX_BIN" exec -c model_reasoning_effort=low -s read-only -o "$report_path" --cd "$repo_path" "$prompt" >"$stdout_path" 2>"$stderr_path"; then
      meta 'Codex git review completed successfully.'
    else
      code=$?
      meta "Codex git review failed with exit code: $code"
      write_fallback_report "codex_exit_code=$code"
    fi
  fi
else
  meta 'Codex binary not found in PATH or CODEX_BIN.'
  write_fallback_report 'codex_executable_not_available'
fi
cp "$report_path" "$latest_report_path"
printf 'Report: %s\n' "$report_path"
printf 'Latest: %s\n' "$latest_report_path"
