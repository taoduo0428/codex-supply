#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/common.sh"

expected_workspace=""
strict_github_token=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expected-workspace-path) expected_workspace="$2"; shift 2 ;;
    --strict-github-token) strict_github_token=1; shift ;;
    *) printf '[ERROR] Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

issues=0
warnings=0
pass() { printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1"; issues=$((issues + 1)); }
warn_msg() { printf '[WARN] %s\n' "$1"; warnings=$((warnings + 1)); }

if [[ -z "$expected_workspace" && -f "$LAST_INSTALL_PATH" ]]; then
  expected_workspace="$(python3 - "$LAST_INSTALL_PATH" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding='utf-8'))
except Exception:
    print('')
    raise SystemExit(0)
value = str(data.get('workspace_path', '') or '').strip()
print(value)
PY
)"
  if [[ -n "$expected_workspace" ]]; then
    pass "Inferred expected workspace path from install receipt: $expected_workspace"
  fi
fi

expected_plugins=(workspace-core git-review agent-orchestration integration-runtime personal-productivity)
printf 'Checking global plugin directories...\n'
for name in "${expected_plugins[@]}"; do
  path="$PLUGINS_ROOT/$name"
  if [[ -d "$path" ]]; then
    pass "Plugin directory exists: $path"
  else
    fail "Plugin directory missing: $path"
  fi
done

printf '\nChecking global marketplace registry...\n'
if [[ ! -f "$MARKETPLACE_PATH" ]]; then
  fail "Marketplace file missing: $MARKETPLACE_PATH"
else
  pass "Marketplace file exists: $MARKETPLACE_PATH"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    status="${line%%::*}"
    msg="${line#*::}"
    case "$status" in
      PASS) pass "$msg" ;;
      FAIL) fail "$msg" ;;
    esac
  done < <(python3 - "$MARKETPLACE_PATH" "${expected_plugins[@]}" <<'PY'
import json
import os
import sys
path = sys.argv[1]
expected = sys.argv[2:]
try:
    data = json.loads(open(path, encoding='utf-8').read())
except Exception:
    print(f'FAIL::Marketplace JSON parse failed: {path}')
    raise SystemExit(0)
plugins = {item.get('name'): item for item in data.get('plugins', []) if isinstance(item, dict)}
base = os.path.dirname(path)
for name in expected:
    entry = plugins.get(name)
    if not entry:
        print(f'FAIL::Marketplace entry missing: {name}')
        continue
    source = entry.get('source') or {}
    registered = str(source.get('path', '') or '').strip()
    if not registered:
        print(f'FAIL::Marketplace entry has empty path: {name}')
        continue
    print(f'PASS::Marketplace entry found: {name} -> {registered}')
    resolved = registered if os.path.isabs(registered) else os.path.abspath(os.path.join(base, registered))
    if os.path.exists(resolved):
        print(f'PASS::Registered path exists: {resolved}')
    else:
        print(f'FAIL::Registered path missing on disk: {resolved}')
PY
)
fi

printf '\nChecking integration-runtime MCP wiring...\n'
integration_mcp="$PLUGINS_ROOT/integration-runtime/.mcp.json"
if [[ ! -f "$integration_mcp" ]]; then
  fail "integration-runtime MCP file missing: $integration_mcp"
else
  pass "integration-runtime MCP file exists: $integration_mcp"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    status="${line%%::*}"
    msg="${line#*::}"
    case "$status" in
      PASS) pass "$msg" ;;
      FAIL) fail "$msg" ;;
      WARN) warn_msg "$msg" ;;
    esac
  done < <(python3 - "$integration_mcp" "$expected_workspace" <<'PY'
import json
import sys
path = sys.argv[1]
expected = sys.argv[2].strip()
required = ['playwright', 'filesystem', 'fetch', 'git', 'github', 'openaiDeveloperDocs']
try:
    data = json.loads(open(path, encoding='utf-8').read())
except Exception:
    print(f'FAIL::integration-runtime MCP JSON parse failed: {path}')
    raise SystemExit(0)
servers = data.get('mcpServers', {})
for name in required:
    if name in servers:
        print(f'PASS::MCP server exists: {name}')
    else:
        print(f'FAIL::MCP server missing: {name}')
if expected:
    fs_args = list((servers.get('filesystem') or {}).get('args') or [])
    git_args = list((servers.get('git') or {}).get('args') or [])
    fs_path = fs_args[-1] if fs_args else ''
    try:
        git_path = git_args[git_args.index('--repository') + 1]
    except Exception:
        git_path = ''
    if fs_path == expected:
        print('PASS::filesystem workspace path matches expected value')
    else:
        print(f"FAIL::filesystem workspace path mismatch. expected='{expected}' actual='{fs_path}'")
    if git_path == expected:
        print('PASS::git workspace path matches expected value')
    else:
        print(f"FAIL::git workspace path mismatch. expected='{expected}' actual='{git_path}'")
else:
    print('WARN::Expected workspace path not provided; skipped workspace path equality checks.')
PY
)
fi

printf '\nChecking workspace git topology...\n'
if [[ -n "$expected_workspace" ]]; then
  if [[ -d "$expected_workspace/.git" ]]; then
    workspace_top="$(git -C "$expected_workspace" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -z "$workspace_top" ]]; then
      warn_msg "Unable to resolve git top-level for expected workspace: $expected_workspace"
    elif [[ "$workspace_top" == "$expected_workspace" ]]; then
      pass "Workspace is an independent git repository: $expected_workspace"
    else
      warn_msg "Workspace is nested in a parent git repository. workspace='$expected_workspace' repo_top='$workspace_top'"
    fi
  else
    warn_msg "Expected workspace is not initialized as a git repository: $expected_workspace"
  fi
else
  warn_msg 'Expected workspace path not provided; skipped git topology check.'
fi

printf '\nChecking executable paths...\n'
if [[ -x "$GLOBAL_PYTHON" ]]; then
  pass "Global python exists: $GLOBAL_PYTHON"
else
  warn_msg "Global python missing at: $GLOBAL_PYTHON (fallback to system python3/module checks)"
fi

if [[ -x "$GLOBAL_FETCH_BIN" ]]; then
  pass "Fetch executable exists: $GLOBAL_FETCH_BIN"
elif python3 -c 'import mcp_server_fetch' >/dev/null 2>&1; then
  pass "Fetch runtime available via python3 module: mcp_server_fetch"
else
  fail "Fetch runtime missing (neither $GLOBAL_FETCH_BIN nor python module mcp_server_fetch available)"
fi

if [[ -x "$GLOBAL_GIT_BIN" ]]; then
  pass "Git executable exists: $GLOBAL_GIT_BIN"
elif python3 -c 'import mcp_server_git' >/dev/null 2>&1; then
  pass "Git runtime available via python3 module: mcp_server_git"
else
  fail "Git runtime missing (neither $GLOBAL_GIT_BIN nor python module mcp_server_git available)"
fi
if [[ -n "$CODEX_BIN" && -x "$CODEX_BIN" ]]; then
  if "$CODEX_BIN" --version >/dev/null 2>&1; then
    pass "codex executable is runnable: $CODEX_BIN"
  else
    fail "codex executable exists but failed to run --version: $CODEX_BIN"
  fi
else
  fail 'codex executable not found in PATH or CODEX_BIN'
fi

printf '\nChecking WSL secret-service for OAuth/keyring...\n'
if [[ -n "${WSL_DISTRO_NAME:-}" || -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
  has_deps=true
  for cmd in gnome-keyring-daemon secret-tool dbus-send; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      has_deps=false
      warn_msg "Missing dependency for secret-service: $cmd"
    fi
  done
  if [[ "$has_deps" == true ]]; then
    if dbus-send --session --dest=org.freedesktop.secrets --type=method_call /org/freedesktop/secrets org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; then
      pass 'Secret-service is reachable on session bus.'
    else
      warn_msg 'Secret-service is not active on current session bus. Run: bash ~/.agents/automation/scripts/setup_wsl_secret_service.sh'
    fi
  else
    warn_msg 'WSL keyring deps are incomplete. Run: bash ~/.agents/automation/scripts/setup_wsl_secret_service.sh'
  fi
else
  pass 'Not running in WSL; skipped secret-service check.'
fi

printf '\nChecking GitHub token for GitHub MCP...\n'
if [[ -n "${GITHUB_TOKEN:-}" || -n "${GITHUB_PAT:-}" ]]; then
  token_files=()
  [[ -f "$AUTOMATION_ENV_FILE" ]] && token_files+=("$AUTOMATION_ENV_FILE")
  [[ -f "$CODEX_ENV_FILE" && "$CODEX_ENV_FILE" != "$AUTOMATION_ENV_FILE" ]] && token_files+=("$CODEX_ENV_FILE")
  if [[ "${#token_files[@]}" -gt 0 ]]; then
    pass "GitHub token env var is present (env files loaded: ${token_files[*]})."
  else
    pass 'GitHub token env var is present in current shell.'
  fi
else
  suggestion="Set GITHUB_TOKEN or GITHUB_PAT in shell, or add it to $AUTOMATION_ENV_FILE"
  if [[ "$strict_github_token" -eq 1 ]]; then
    fail "GITHUB_TOKEN/GITHUB_PAT is not set in current shell. $suggestion"
  else
    warn_msg "GITHUB_TOKEN/GITHUB_PAT is not set in current shell. GitHub MCP may fail authentication. $suggestion"
  fi
fi

printf '\n'
if [[ "$issues" -gt 0 ]]; then
  printf 'Validation failed with %d issue(s).\n' "$issues" >&2
  exit 1
fi
if [[ "$warnings" -gt 0 ]]; then
  printf 'Validation passed with %d warning(s).\n' "$warnings"
else
  printf 'All required global runtime checks passed.\n'
fi
