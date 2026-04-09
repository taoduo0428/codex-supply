#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/common.sh"

repo_path="${1:-$(pwd)}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-path) repo_path="$2"; shift 2 ;;
    --active-repo-file) ACTIVE_REPO_FILE="$2"; shift 2 ;;
    *) printf '[ERROR] Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

repo_path="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$repo_path")"
if ! test_git_repo "$repo_path"; then
  printf '[ERROR] Path is not a git repo: %s\n' "$repo_path" >&2
  exit 1
fi
ensure_dir "$(dirname "$ACTIVE_REPO_FILE")"
printf '%s\n' "$repo_path" > "$ACTIVE_REPO_FILE"
printf 'Active repo updated: %s\n' "$repo_path"
printf 'File: %s\n' "$ACTIVE_REPO_FILE"
