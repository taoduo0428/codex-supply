#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
AUTOMATION_HOME="${AUTOMATION_HOME:-$AGENTS_HOME/automation}"
AUTOMATION_SCRIPTS_DIR="${AUTOMATION_SCRIPTS_DIR:-$AUTOMATION_HOME/scripts}"
ACTIVE_REPO_FILE="${ACTIVE_REPO_FILE:-$AGENTS_HOME/active-repo.txt}"
PLUGINS_ROOT="${PLUGINS_ROOT:-$AGENTS_HOME/plugins/plugins}"
MARKETPLACE_PATH="${MARKETPLACE_PATH:-$AGENTS_HOME/plugins/marketplace.json}"
LAST_INSTALL_PATH="${LAST_INSTALL_PATH:-$AGENTS_HOME/plugins/last-global-install.json}"
GLOBAL_TOOLS_VENV="${GLOBAL_TOOLS_VENV:-$CODEX_HOME/venvs/global-tools}"
GLOBAL_PYTHON="${GLOBAL_PYTHON:-$GLOBAL_TOOLS_VENV/bin/python}"
GLOBAL_PRE_COMMIT="${GLOBAL_PRE_COMMIT:-$GLOBAL_TOOLS_VENV/bin/pre-commit}"
GLOBAL_FETCH_BIN="${GLOBAL_FETCH_BIN:-$GLOBAL_TOOLS_VENV/bin/mcp-server-fetch}"
GLOBAL_GIT_BIN="${GLOBAL_GIT_BIN:-$GLOBAL_TOOLS_VENV/bin/mcp-server-git}"
if command -v codex >/dev/null 2>&1; then
  CODEX_BIN_DEFAULT="$(command -v codex)"
else
  CODEX_BIN_DEFAULT=""
fi
CODEX_BIN="${CODEX_BIN:-$CODEX_BIN_DEFAULT}"
AUTOMATION_ENV_FILE="${AUTOMATION_ENV_FILE:-$AUTOMATION_HOME/.env}"
CODEX_ENV_FILE="${CODEX_ENV_FILE:-$CODEX_HOME/.env}"

ensure_dir() {
  mkdir -p "$1"
}

load_optional_env_file() {
  local file="${1:-}"
  [[ -n "$file" && -f "$file" ]] || return 0
  local had_errexit=0
  local had_nounset=0
  [[ "$-" == *e* ]] && had_errexit=1
  [[ "$-" == *u* ]] && had_nounset=1
  set +e
  set +u
  set -a
  # shellcheck disable=SC1090
  source "$file"
  local status=$?
  set +a
  [[ "$had_errexit" -eq 1 ]] && set -e
  [[ "$had_nounset" -eq 1 ]] && set -u
  if [[ "$status" -ne 0 ]]; then
    printf '[WARN] Failed to source env file: %s\n' "$file" >&2
  fi
}

load_optional_env_file "$AUTOMATION_ENV_FILE"
if [[ "$CODEX_ENV_FILE" != "$AUTOMATION_ENV_FILE" ]]; then
  load_optional_env_file "$CODEX_ENV_FILE"
fi

is_codex_usable() {
  local bin="${1:-}"
  [[ -n "$bin" && -x "$bin" ]] || return 1
  "$bin" --version >/dev/null 2>&1
}

discover_vscode_codex_candidates() {
  local ext_root="$HOME/.vscode-server/extensions"
  [[ -d "$ext_root" ]] || return 0
  ls -1d "$ext_root"/openai.chatgpt-*-linux-x64/bin/linux-x86_64/codex 2>/dev/null | sort -Vr || true
}

resolve_codex_bin() {
  local explicit="${1:-}"
  local -a candidates=()
  local candidate
  if [[ -n "$explicit" ]]; then
    candidates+=("$explicit")
  fi
  if [[ -n "$CODEX_BIN_DEFAULT" ]]; then
    candidates+=("$CODEX_BIN_DEFAULT")
  fi
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] && candidates+=("$candidate")
  done < <(discover_vscode_codex_candidates)
  candidates+=("$HOME/.local/bin/codex" "$HOME/.npm-global/bin/codex")

  local seen=$'\n'
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" ]] || continue
    if [[ "$seen" == *$'\n'"$candidate"$'\n'* ]]; then
      continue
    fi
    seen+="$candidate"$'\n'
    if is_codex_usable "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf '%s\n' ""
}

test_git_repo() {
  local path_value="${1:-}"
  [[ -n "$path_value" ]] || return 1
  [[ -d "$path_value/.git" ]]
}

read_install_workspace_path() {
  [[ -f "$LAST_INSTALL_PATH" ]] || return 0
  python3 - "$LAST_INSTALL_PATH" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding='utf-8'))
except Exception:
    raise SystemExit(0)
value = str(data.get('workspace_path', '') or '').strip()
if value:
    print(value)
PY
}

resolve_workspace_path() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    printf '%s\n' "$explicit"
    return 0
  fi
  if [[ -n "${CODEX_WORKSPACE_PATH:-}" ]]; then
    printf '%s\n' "$CODEX_WORKSPACE_PATH"
    return 0
  fi
  if [[ -n "${CODEX_WORKSPACE:-}" ]]; then
    printf '%s\n' "$CODEX_WORKSPACE"
    return 0
  fi
  local from_receipt=""
  from_receipt="$(read_install_workspace_path || true)"
  if [[ -n "$from_receipt" ]]; then
    printf '%s\n' "$from_receipt"
    return 0
  fi
  pwd
}

resolve_repo_path() {
  local explicit="${1:-}"
  if test_git_repo "$explicit"; then
    printf '%s\n' "$explicit"
    return 0
  fi
  if test_git_repo "${CODEX_WORKSPACE_PATH:-}"; then
    printf '%s\n' "$CODEX_WORKSPACE_PATH"
    return 0
  fi
  if test_git_repo "${CODEX_WORKSPACE:-}"; then
    printf '%s\n' "$CODEX_WORKSPACE"
    return 0
  fi
  if [[ -f "$ACTIVE_REPO_FILE" ]]; then
    local candidate=""
    candidate="$(grep -m1 -v '^[[:space:]]*$' "$ACTIVE_REPO_FILE" 2>/dev/null | tr -d '\r' || true)"
    if test_git_repo "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  local from_receipt=""
  from_receipt="$(read_install_workspace_path || true)"
  if test_git_repo "$from_receipt"; then
    printf '%s\n' "$from_receipt"
    return 0
  fi
  return 1
}

require_codex_bin() {
  CODEX_BIN="$(resolve_codex_bin "$CODEX_BIN")"
  [[ -n "$CODEX_BIN" ]] || {
    printf '[FAIL] codex executable not found in PATH or CODEX_BIN\n' >&2
    return 1
  }
}

require_global_python() {
  if [[ -x "$GLOBAL_PYTHON" ]]; then
    printf '%s\n' "$GLOBAL_PYTHON"
    return 0
  fi
  command -v python3 >/dev/null 2>&1 && command -v python3 && return 0
  printf '[FAIL] python3 is not available\n' >&2
  return 1
}

json_quote() {
  python3 - "$1" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1], ensure_ascii=False))
PY
}

CODEX_BIN="$(resolve_codex_bin "$CODEX_BIN")"
