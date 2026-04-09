#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

show_help() {
  cat <<'EOF'
Usage:
  ./bootstrap_fresh_global_full.sh \
    [--repo-root <path>] \
    [--workspace-path <path>] \
    [--skills-source-path <path>] \
    [--daily-smoke-time HH:MM] \
    [--git-review-interval-hours N] \
    [--git-review-timeout-seconds N] \
    [--enable-git-review] \
    [--disable-git-review] \
    [--use-symlink] \
    [--codex-home <path>] \
    [--self-improving-source-path <path>] \
    [--proactive-source-path <path>] \
    [--superpowers-source-path <path>] \
    [--openspace-source-path <path>] \
    [--enable-nightly-memory] \
    [--disable-nightly-memory] \
    [--nightly-memory-time HH:MM] \
    [--skip-scheduled-tasks] \
    [--skip-codex-config-sync] \
    [--skip-safety-policy-sync] \
    [--skip-openspace-sync] \
    [--skip-governance-toolkit-sync] \
    [--skip-native-hooks-sync] \
    [--skip-submodule-init]

Notes:
  - Linux/WSL version of the Windows full bootstrap.
  - Keeps append/marker strategy for AGENTS/ACTIVE/rules.
  - Installs runtime governance scripts under ~/.codex/runtime/governance.
  - If module source paths are omitted, auto-detect from bundle external/* layout.
  - If external modules are missing, script auto-attempts `git submodule update --init --recursive` (unless skipped).
EOF
}

step() { printf '[STEP] %s\n' "$1"; }
info() { printf '[INFO] %s\n' "$1"; }
ok() { printf '[OK] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1" >&2; }
die() { printf '[ERROR] %s\n' "$1" >&2; exit 1; }

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
}

resolve_path() {
  local raw="${1:-}"
  python3 - "$raw" <<'PY'
import os, re, sys
p = sys.argv[1] or ""
if not p.strip():
    print("")
    raise SystemExit(0)
if re.match(r"^[A-Za-z]:\\", p):
    drive = p[0].lower()
    rest = p[2:].replace("\\", "/")
    p = f"/mnt/{drive}/{rest}"
print(os.path.abspath(os.path.expanduser(p)))
PY
}

first_existing_path() {
  local raw=""
  local resolved=""
  for raw in "$@"; do
    [[ -n "$raw" ]] || continue
    resolved="$(resolve_path "$raw")"
    if [[ -n "$resolved" && -e "$resolved" ]]; then
      printf '%s\n' "$resolved"
      return 0
    fi
  done
  printf '\n'
}

try_init_submodules_if_needed() {
  local bundle_root="$1"
  local skip_flag="$2"
  shift 2
  local missing="0"
  local path=""
  for path in "$@"; do
    [[ -d "$path" ]] || { missing="1"; break; }
  done
  [[ "$missing" == "1" ]] || return 0
  if [[ "$skip_flag" == "1" ]]; then
    info "skip-submodule-init enabled; skip submodule auto-init."
    return 0
  fi
  if [[ ! -d "$bundle_root/.git" ]]; then
    info "Bundle root is not a git repository; skip submodule auto-init."
    return 0
  fi
  step "External modules missing; attempting submodule init/update"
  if (cd "$bundle_root" && git submodule update --init --recursive); then
    ok "Submodule init completed."
  else
    warn "Submodule init failed; continue with existing local files."
  fi
}

ensure_dir() {
  mkdir -p "$1"
}

ensure_file() {
  local target="$1"
  local content="${2:-}"
  if [[ ! -f "$target" ]]; then
    printf '%s' "$content" | write_utf8_nobom "$target"
  fi
}

write_utf8_nobom() {
  local target="$1"
  python3 -c '
from pathlib import Path
import sys
target = Path(sys.argv[1])
data = sys.stdin.read()
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(data, encoding="utf-8", newline="\n")
' "$target"
}

sync_dir_mirror() {
  local src="$1"
  local dst="$2"
  local label="$3"
  [[ -d "$src" ]] || die "$label source not found: $src"
  mkdir -p "$dst"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src"/ "$dst"/
  else
    python3 - "$src" "$dst" <<'PY'
from pathlib import Path
import shutil
import sys
src = Path(sys.argv[1])
dst = Path(sys.argv[2])
dst.mkdir(parents=True, exist_ok=True)
for child in dst.iterdir():
    if child.is_dir():
        shutil.rmtree(child)
    else:
        child.unlink()
for child in src.iterdir():
    target = dst / child.name
    if child.is_dir():
        shutil.copytree(child, target)
    else:
        shutil.copy2(child, target)
PY
  fi
}

ensure_symlink() {
  local link_path="$1"
  local target_path="$2"
  [[ -e "$target_path" ]] || die "Symlink target not found: $target_path"
  mkdir -p "$(dirname "$link_path")"
  if [[ -L "$link_path" ]]; then
    local current
    current="$(readlink "$link_path" || true)"
    if [[ "$current" == "$target_path" ]]; then
      return 0
    fi
    rm -f "$link_path"
  elif [[ -e "$link_path" ]]; then
    local backup="${link_path}.backup.$(date +%Y%m%d%H%M%S)"
    mv "$link_path" "$backup"
    warn "Existing non-link path moved to backup: $backup"
  fi
  ln -s "$target_path" "$link_path"
}

ensure_marked_block() {
  local path="$1"
  local start="$2"
  local end="$3"
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  python3 - "$path" "$start" "$end" "$tmp" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
start = sys.argv[2]
end = sys.argv[3]
block = Path(sys.argv[4]).read_text(encoding="utf-8")
text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
if pattern.search(text):
    updated = pattern.sub(block, text, count=1)
else:
    updated = (text.rstrip() + "\n\n" + block) if text.strip() else block
if not updated.endswith("\n"):
    updated += "\n"
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(updated, encoding="utf-8", newline="\n")
PY
  rm -f "$tmp"
}

append_block_if_missing() {
  local path="$1"
  local marker="$2"
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  python3 - "$path" "$marker" "$tmp" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
marker = sys.argv[2]
block = Path(sys.argv[3]).read_text(encoding="utf-8")
text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
if marker in text:
    raise SystemExit(0)
updated = (text.rstrip() + "\n\n" + block) if text.strip() else block
if not updated.endswith("\n"):
    updated += "\n"
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(updated, encoding="utf-8", newline="\n")
PY
  rm -f "$tmp"
}

add_or_update_cron_job() {
  local tag="$1"
  local expr="$2"
  local cmd="$3"
  if ! command -v crontab >/dev/null 2>&1; then
    warn "crontab not found; skip cron job: $tag"
    return 0
  fi
  local current
  current="$(crontab -l 2>/dev/null || true)"
  local cleaned
  cleaned="$(printf '%s\n' "$current" | grep -v "# $tag" | grep -v "$cmd" || true)"
  {
    printf '%s\n' "$cleaned"
    printf '%s %s # %s\n' "$expr" "$cmd" "$tag"
  } | sed '/^[[:space:]]*$/d' | crontab -
}

ensure_codex_config_mcp() {
  local config_path="$1"
  local workspace="$2"
  local openspace_workspace="$3"
  local openspace_host_skill_dirs="$4"
  local fetch_command="${5:-}"
  local git_command="${6:-}"

  python3 - "$config_path" "$workspace" "$openspace_workspace" "$openspace_host_skill_dirs" "$fetch_command" "$git_command" <<'PY'
from pathlib import Path
import re
import sys

config_path = Path(sys.argv[1])
workspace = sys.argv[2]
openspace_workspace = sys.argv[3]
openspace_host_skill_dirs = sys.argv[4]
fetch_command = sys.argv[5].strip()
git_command = sys.argv[6].strip()

text = config_path.read_text(encoding="utf-8", errors="replace") if config_path.exists() else ""

def ensure_section_block(src: str, header: str, body_lines: list[str]) -> str:
    block = header + "\n" + "\n".join(body_lines)
    pattern = re.compile(r"(?ms)^\s*" + re.escape(header) + r"\s*$.*?(?=^\s*\[|\Z)")
    if pattern.search(src):
        return src
    if src.strip():
        return src.rstrip() + "\n\n" + block + "\n"
    return block + "\n"

def ensure_key_in_section(src: str, header: str, key: str, key_line: str) -> str:
    sec_pattern = re.compile(r"(?ms)^\s*" + re.escape(header) + r"\s*$.*?(?=^\s*\[|\Z)")
    m = sec_pattern.search(src)
    if not m:
        return ensure_section_block(src, header, [key_line])
    sec_text = m.group(0)
    if re.search(r"(?m)^\s*" + re.escape(key) + r"\s*=", sec_text):
        return src
    new_sec = sec_text.rstrip() + "\n" + key_line + "\n"
    return src[:m.start()] + new_sec + src[m.end():]

text = ensure_key_in_section(text, "[features]", "multi_agent", "multi_agent = true")
text = ensure_key_in_section(text, "[features]", "codex_hooks", "codex_hooks = true")

text = ensure_section_block(text, "[mcp_servers.playwright]", [
    'command = "npx"',
    'args = ["-y", "@playwright/mcp@latest"]',
])
text = ensure_section_block(text, "[mcp_servers.filesystem]", [
    'command = "npx"',
    f'args = ["-y", "@modelcontextprotocol/server-filesystem", "{workspace}"]',
])
if fetch_command:
    text = ensure_section_block(text, "[mcp_servers.fetch]", [
        f'command = "{fetch_command}"',
        'args = []',
    ])
else:
    text = ensure_section_block(text, "[mcp_servers.fetch]", [
        'command = "python3"',
        'args = ["-m", "mcp_server_fetch"]',
    ])
if git_command:
    text = ensure_section_block(text, "[mcp_servers.git]", [
        f'command = "{git_command}"',
        f'args = ["--repository", "{workspace}"]',
    ])
else:
    text = ensure_section_block(text, "[mcp_servers.git]", [
        'command = "python3"',
        f'args = ["-m", "mcp_server_git", "--repository", "{workspace}"]',
    ])
text = ensure_section_block(text, "[mcp_servers.openaiDeveloperDocs]", [
    'url = "https://developers.openai.com/mcp"',
])

if openspace_workspace and openspace_host_skill_dirs:
    text = ensure_section_block(text, "[mcp_servers.openspace]", [
        'command = "python3"',
        'args = ["-m", "openspace.mcp_server"]',
    ])
    text = ensure_section_block(text, "[mcp_servers.openspace.env]", [
        f'OPENSPACE_WORKSPACE = "{openspace_workspace}"',
        f'OPENSPACE_HOST_SKILL_DIRS = "{openspace_host_skill_dirs}"',
        f'PYTHONPATH = "{openspace_workspace}"',
    ])

if not text.endswith("\n"):
    text += "\n"
config_path.parent.mkdir(parents=True, exist_ok=True)
config_path.write_text(text, encoding="utf-8", newline="\n")
PY
}

ensure_native_hooks_config() {
  local hooks_path="$1"
  local hook_script="$2"
  python3 - "$hooks_path" "$hook_script" <<'PY'
from pathlib import Path
import json
import sys

hooks_path = Path(sys.argv[1])
hook_script = sys.argv[2]
hook_cmd = f'bash "{hook_script}"'

if hooks_path.exists():
    try:
        root = json.loads(hooks_path.read_text(encoding="utf-8"))
    except Exception:
        backup = hooks_path.with_suffix(hooks_path.suffix + ".bak")
        hooks_path.replace(backup)
        root = {}
else:
    root = {}

if not isinstance(root, dict):
    root = {}
if "hooks" not in root or not isinstance(root["hooks"], dict):
    root["hooks"] = {}

managed = [
    ("SessionStart", "startup|resume", "Loading global governance context"),
    ("UserPromptSubmit", "", "Classifying governance profile"),
    ("PreToolUse", "Bash", "Running governance preflight"),
    ("PostToolUse", "Bash", "Reviewing command outcome"),
]

for event, matcher, status in managed:
    entries = root["hooks"].get(event, [])
    if not isinstance(entries, list):
        entries = []
    filtered = []
    for entry in entries:
        keep = True
        if isinstance(entry, dict):
            hooks = entry.get("hooks", [])
            if isinstance(hooks, list):
                for h in hooks:
                    if isinstance(h, dict) and h.get("command") == hook_cmd:
                        keep = False
        if keep:
            filtered.append(entry)
    new_entry = {
        "hooks": [
            {
                "type": "command",
                "command": hook_cmd,
                "statusMessage": status,
            }
        ]
    }
    if matcher:
        new_entry["matcher"] = matcher
    filtered.append(new_entry)
    root["hooks"][event] = filtered

hooks_path.parent.mkdir(parents=True, exist_ok=True)
hooks_path.write_text(json.dumps(root, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

ensure_governance_toolkit_scripts() {
  local governance_dir="$1"
  ensure_dir "$governance_dir"

  write_utf8_nobom "$governance_dir/codex_task_contract.template.json" <<'EOF'
{
  "contract_version": "1.0",
  "project_type": "general",
  "quality_gates": {
    "tests": true,
    "lint": true,
    "typecheck": true,
    "build": false
  },
  "risk_profile": "standard",
  "notes": "Use strict profile for data migration, external integrations, and destructive operations."
}
EOF

  write_utf8_nobom "$governance_dir/codex_crawler_contract.template.json" <<'EOF'
{
  "contract_version": "1.0",
  "project_type": "crawler",
  "quality_gates": {
    "tests": false,
    "lint": true,
    "typecheck": false,
    "build": false
  },
  "crawler_limits": {
    "request_timeout_seconds": 20,
    "max_retries": 4,
    "concurrency": 8,
    "download_delay_seconds": 0.5
  }
}
EOF

  write_utf8_nobom "$governance_dir/codex_preflight_gate.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

TASK_TEXT=""
COMMAND_LINE=""
AS_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-text) TASK_TEXT="${2:-}"; shift 2 ;;
    --command-line) COMMAND_LINE="${2:-}"; shift 2 ;;
    --as-json) AS_JSON=1; shift ;;
    *) echo "[WARN] Unknown arg: $1" >&2; shift ;;
  esac
done

to_lower() {
  python3 - "$1" <<'PY'
import sys
print((sys.argv[1] or "").lower())
PY
}

task_lc="$(to_lower "$TASK_TEXT")"
cmd_lc="$(to_lower "$COMMAND_LINE")"

profile="standard"
decision="allow"
reason=""

if [[ "$task_lc" =~ (migrate|migration|delete|cleanup|external\ api|payment|checkpoint|resume|concurrency|queue|deploy|training|inference|gpu|数据迁移|删除|并发|训练|推理|部署) ]]; then
  profile="strict"
elif [[ "$task_lc" =~ (readme|docs|comment|typo|format|文档|注释) ]]; then
  profile="light"
fi

if [[ "$cmd_lc" =~ (^|[[:space:]])rm[[:space:]] ]] || [[ "$cmd_lc" =~ (^|[[:space:]])del[[:space:]] ]] || [[ "$cmd_lc" =~ (^|[[:space:]])rmdir[[:space:]] ]] || [[ "$cmd_lc" =~ remove-item ]]; then
  decision="block"
  reason="destructive command requires explicit user confirmation"
fi
if [[ "$cmd_lc" =~ git[[:space:]]+reset[[:space:]]+--hard ]] || [[ "$cmd_lc" =~ git[[:space:]]+clean[[:space:]]+-fd ]]; then
  decision="block"
  reason="destructive git command requires explicit user confirmation"
fi
if [[ "$decision" == "allow" && "$profile" == "strict" && -n "$COMMAND_LINE" ]]; then
  decision="warn"
  reason="strict profile: include failure map and side-effect notes in output"
fi

context="Governance profile=$profile decision=$decision"

if [[ "$AS_JSON" -eq 1 ]]; then
  python3 - "$decision" "$profile" "$reason" "$context" <<'PY'
import json, sys
decision, profile, reason, context = sys.argv[1:5]
print(json.dumps({
  "decision": decision,
  "profile": profile,
  "reason": reason,
  "additionalContext": context
}, ensure_ascii=False))
PY
else
  printf 'decision=%s profile=%s\n' "$decision" "$profile"
  if [[ -n "$reason" ]]; then
    printf 'reason=%s\n' "$reason"
  fi
fi

if [[ "$decision" == "block" ]]; then
  exit 2
fi
exit 0
EOF

  write_utf8_nobom "$governance_dir/codex_native_governance_hook.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRE="$SCRIPT_DIR/codex_preflight_gate.sh"
INPUT="$(cat || true)"

if [[ -z "$INPUT" ]]; then
  exit 0
fi

PY_OUT="$(python3 - "$INPUT" <<'PY'
import json, sys
raw = sys.argv[1]
try:
    obj = json.loads(raw)
except Exception:
    print("||")
    raise SystemExit(0)

def pick(d, names):
    for n in names:
        if isinstance(d, dict) and n in d and d[n] is not None:
            return d[n]
    return ""

event = pick(obj, ["event", "hook_event_name", "hookEventName"])
task = pick(obj, ["prompt", "task", "taskText", "user_prompt", "text"])
cmd = pick(obj, ["command", "command_line", "shell_command", "tool_input"])
print(f"{event}|{task}|{cmd}")
PY
)"

EVENT="${PY_OUT%%|*}"
REST="${PY_OUT#*|}"
TASK="${REST%%|*}"
CMD="${REST#*|}"

if [[ "$EVENT" == "PreToolUse" || "$EVENT" == "UserPromptSubmit" ]]; then
  if "$PRE" --task-text "$TASK" --command-line "$CMD" --as-json >/dev/null; then
    exit 0
  else
    code=$?
    if [[ $code -eq 2 ]]; then
      echo "[HOOK] blocked by governance preflight: $CMD" >&2
    fi
    exit "$code"
  fi
fi
exit 0
EOF

  write_utf8_nobom "$governance_dir/codex_doctor.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

CODEX_HOME="${HOME}/.codex"
AS_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --codex-home) CODEX_HOME="$2"; shift 2 ;;
    --as-json) AS_JSON=1; shift ;;
    *) echo "[WARN] Unknown arg: $1" >&2; shift ;;
  esac
done

check_names=()
check_pass=()
check_detail=()

add_check() {
  check_names+=("$1")
  check_pass+=("$2")
  check_detail+=("$3")
}

exists() {
  [[ -e "$1" ]] && echo "true" || echo "false"
}

cfg="$CODEX_HOME/config.toml"
agents="$CODEX_HOME/AGENTS.md"
active="$CODEX_HOME/memories/ACTIVE.md"
rules="$CODEX_HOME/rules/default.rules"
gov="$CODEX_HOME/runtime/governance"
hooks="$CODEX_HOME/hooks.json"

add_check "config_exists" "$(exists "$cfg")" "$cfg"
add_check "agents_exists" "$(exists "$agents")" "$agents"
add_check "active_exists" "$(exists "$active")" "$active"
add_check "rules_exists" "$(exists "$rules")" "$rules"
add_check "governance_dir_exists" "$(exists "$gov")" "$gov"
add_check "hooks_exists" "$(exists "$hooks")" "$hooks"

if [[ -f "$cfg" ]]; then
  grep -Eq '^\s*codex_hooks\s*=\s*true\s*$' "$cfg" && add_check "codex_hooks_feature" "true" "codex_hooks=true" || add_check "codex_hooks_feature" "false" "missing codex_hooks=true"
  grep -Eq '^\[mcp_servers\.playwright\]$' "$cfg" && add_check "mcp_playwright" "true" "present" || add_check "mcp_playwright" "false" "missing"
  grep -Eq '^\[mcp_servers\.filesystem\]$' "$cfg" && add_check "mcp_filesystem" "true" "present" || add_check "mcp_filesystem" "false" "missing"
  grep -Eq '^\[mcp_servers\.git\]$' "$cfg" && add_check "mcp_git" "true" "present" || add_check "mcp_git" "false" "missing"
fi

if [[ -f "$agents" ]]; then
  grep -q 'codex-global-reliability-policy:start' "$agents" && add_check "agents_reliability_marker" "true" "present" || add_check "agents_reliability_marker" "false" "missing"
  grep -q 'codex-global-governance-policy:start' "$agents" && add_check "agents_governance_marker" "true" "present" || add_check "agents_governance_marker" "false" "missing"
fi

if [[ -f "$active" ]]; then
  grep -q 'codex-active-reliability-policy:start' "$active" && add_check "active_reliability_marker" "true" "present" || add_check "active_reliability_marker" "false" "missing"
fi

if [[ -f "$rules" ]]; then
  grep -q '^# codex-global-delete-guard:start$' "$rules" && add_check "rules_delete_guard_marker" "true" "present" || add_check "rules_delete_guard_marker" "false" "missing"
fi

if [[ -f "$hooks" ]]; then
  grep -q 'codex_native_governance_hook\.sh' "$hooks" && add_check "hooks_native_dispatcher" "true" "present" || add_check "hooks_native_dispatcher" "false" "missing"
fi

if [[ -d "$gov" ]]; then
  for f in codex_preflight_gate.sh codex_doctor.sh codex_regression_check.sh codex_project_contract_check.sh codex_project_contract_init.sh codex_crawler_project_init.sh codex_crawler_smoke_test.sh codex_native_governance_hook.sh; do
    [[ -f "$gov/$f" ]] && add_check "script_${f}" "true" "present" || add_check "script_${f}" "false" "missing"
  done
fi

failed=0
for i in "${!check_names[@]}"; do
  if [[ "${check_pass[$i]}" != "true" ]]; then
    failed=$((failed + 1))
  fi
done

if [[ "$AS_JSON" -eq 1 ]]; then
  python3 - "$failed" "$(printf '%s\n' "${check_names[@]}")" "$(printf '%s\n' "${check_pass[@]}")" "$(printf '%s\n' "${check_detail[@]}")" <<'PY'
import json, sys
failed = int(sys.argv[1])
names = sys.argv[2].splitlines()
passes = sys.argv[3].splitlines()
details = sys.argv[4].splitlines()
checks = []
for i, n in enumerate(names):
    checks.append({"name": n, "pass": passes[i] == "true", "detail": details[i] if i < len(details) else ""})
print(json.dumps({"ok": failed == 0, "failed": failed, "checks": checks}, ensure_ascii=False))
PY
else
  for i in "${!check_names[@]}"; do
    if [[ "${check_pass[$i]}" == "true" ]]; then
      printf '[OK] %s - %s\n' "${check_names[$i]}" "${check_detail[$i]}"
    else
      printf '[FAIL] %s - %s\n' "${check_names[$i]}" "${check_detail[$i]}"
    fi
  done
fi

if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
exit 0
EOF

  write_utf8_nobom "$governance_dir/codex_regression_check.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

CODEX_HOME="${HOME}/.codex"
BUNDLE_ROOT=""
AS_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --codex-home) CODEX_HOME="$2"; shift 2 ;;
    --bundle-root) BUNDLE_ROOT="$2"; shift 2 ;;
    --as-json) AS_JSON=1; shift ;;
    *) echo "[WARN] Unknown arg: $1" >&2; shift ;;
  esac
done

checks=()
add() {
  checks+=("$1|$2|$3")
}

file_exists() {
  [[ -e "$1" ]] && echo "true" || echo "false"
}

add "doctor_script" "$(file_exists "$CODEX_HOME/runtime/governance/codex_doctor.sh")" "$CODEX_HOME/runtime/governance/codex_doctor.sh"
add "preflight_script" "$(file_exists "$CODEX_HOME/runtime/governance/codex_preflight_gate.sh")" "$CODEX_HOME/runtime/governance/codex_preflight_gate.sh"
add "regression_script" "$(file_exists "$CODEX_HOME/runtime/governance/codex_regression_check.sh")" "$CODEX_HOME/runtime/governance/codex_regression_check.sh"
add "hooks_json" "$(file_exists "$CODEX_HOME/hooks.json")" "$CODEX_HOME/hooks.json"
add "agents_marker_runtime" "$(grep -q 'codex-global-policy-runtime:start' "$CODEX_HOME/AGENTS.md" 2>/dev/null && echo true || echo false)" "codex-global-policy-runtime marker"

if [[ -n "$BUNDLE_ROOT" ]]; then
  if [[ -e "$BUNDLE_ROOT/wsl/bootstrap_fresh_global_full.sh" ]]; then
    add "bundle_bootstrap_linux" "$(file_exists "$BUNDLE_ROOT/wsl/bootstrap_fresh_global_full.sh")" "$BUNDLE_ROOT/wsl/bootstrap_fresh_global_full.sh"
    add "bundle_guide_linux" "$(file_exists "$BUNDLE_ROOT/wsl/GLOBAL_BOOTSTRAP_TEAM_GUIDE.md")" "$BUNDLE_ROOT/wsl/GLOBAL_BOOTSTRAP_TEAM_GUIDE.md"
    add "bundle_teammate_linux" "$(file_exists "$BUNDLE_ROOT/wsl/TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md")" "$BUNDLE_ROOT/wsl/TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md"
  else
    add "bundle_bootstrap_linux" "$(file_exists "$BUNDLE_ROOT/WSL/bootstrap_fresh_global_full.sh")" "$BUNDLE_ROOT/WSL/bootstrap_fresh_global_full.sh"
    add "bundle_guide_linux" "$(file_exists "$BUNDLE_ROOT/WSL/GLOBAL_BOOTSTRAP_TEAM_GUIDE.md")" "$BUNDLE_ROOT/WSL/GLOBAL_BOOTSTRAP_TEAM_GUIDE.md"
    add "bundle_teammate_linux" "$(file_exists "$BUNDLE_ROOT/WSL/TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md")" "$BUNDLE_ROOT/WSL/TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md"
  fi
fi

failed=0
for row in "${checks[@]}"; do
  pass="$(echo "$row" | cut -d'|' -f2)"
  [[ "$pass" == "true" ]] || failed=$((failed + 1))
done

if [[ "$AS_JSON" -eq 1 ]]; then
  python3 - "$failed" "$(printf '%s\n' "${checks[@]}")" <<'PY'
import json, sys
failed = int(sys.argv[1])
rows = [r for r in sys.argv[2].splitlines() if r.strip()]
checks = []
for r in rows:
    name, passed, detail = r.split("|", 2)
    checks.append({"name": name, "pass": passed == "true", "detail": detail})
print(json.dumps({"ok": failed == 0, "failed": failed, "checks": checks}, ensure_ascii=False))
PY
else
  for row in "${checks[@]}"; do
    name="$(echo "$row" | cut -d'|' -f1)"
    pass="$(echo "$row" | cut -d'|' -f2)"
    detail="$(echo "$row" | cut -d'|' -f3-)"
    if [[ "$pass" == "true" ]]; then
      printf '[OK] %s - %s\n' "$name" "$detail"
    else
      printf '[FAIL] %s - %s\n' "$name" "$detail"
    fi
  done
fi

[[ "$failed" -eq 0 ]] || exit 1
EOF

  write_utf8_nobom "$governance_dir/codex_project_contract_init.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROJECT_ROOT=""
FORCE=0
INSTALL_PRE_COMMIT_HOOK=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --install-pre-commit-hook) INSTALL_PRE_COMMIT_HOOK=1; shift ;;
    *) echo "[WARN] Unknown arg: $1" >&2; shift ;;
  esac
done

[[ -n "$PROJECT_ROOT" ]] || { echo "[ERROR] --project-root is required" >&2; exit 1; }
PROJECT_ROOT="$(python3 -c 'import os,sys;print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$PROJECT_ROOT")"
mkdir -p "$PROJECT_ROOT"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/codex_task_contract.template.json"

CONTRACT="$PROJECT_ROOT/.codex-task-contract.json"
PRE_COMMIT="$PROJECT_ROOT/.pre-commit-config.yaml"

if [[ ! -f "$CONTRACT" || "$FORCE" -eq 1 ]]; then
  cp "$TEMPLATE" "$CONTRACT"
  echo "[OK] wrote $CONTRACT"
else
  echo "[INFO] keep existing $CONTRACT"
fi

if [[ ! -f "$PRE_COMMIT" || "$FORCE" -eq 1 ]]; then
  cat >"$PRE_COMMIT" <<'YAML'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: check-merge-conflict
      - id: end-of-file-fixer
      - id: trailing-whitespace
YAML
  echo "[OK] wrote $PRE_COMMIT"
else
  echo "[INFO] keep existing $PRE_COMMIT"
fi

if [[ "$INSTALL_PRE_COMMIT_HOOK" -eq 1 ]]; then
  if command -v pre-commit >/dev/null 2>&1; then
    (cd "$PROJECT_ROOT" && pre-commit install)
    echo "[OK] pre-commit hook installed"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m pip install --user pre-commit >/dev/null 2>&1 || true
    if command -v pre-commit >/dev/null 2>&1; then
      (cd "$PROJECT_ROOT" && pre-commit install)
      echo "[OK] pre-commit hook installed"
    else
      echo "[WARN] pre-commit unavailable after install attempt"
    fi
  else
    echo "[WARN] skip pre-commit install; python3 not found"
  fi
fi
EOF

  write_utf8_nobom "$governance_dir/codex_project_contract_check.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROJECT_ROOT=""
FAIL_ON_MISSING_CONTRACT=0
AS_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --fail-on-missing-contract) FAIL_ON_MISSING_CONTRACT=1; shift ;;
    --as-json) AS_JSON=1; shift ;;
    *) echo "[WARN] Unknown arg: $1" >&2; shift ;;
  esac
done

[[ -n "$PROJECT_ROOT" ]] || { echo "[ERROR] --project-root is required" >&2; exit 1; }
PROJECT_ROOT="$(python3 -c 'import os,sys;print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$PROJECT_ROOT")"
CONTRACT="$PROJECT_ROOT/.codex-task-contract.json"
PRE_COMMIT="$PROJECT_ROOT/.pre-commit-config.yaml"

status=0
msg=()

if [[ ! -f "$CONTRACT" ]]; then
  if [[ "$FAIL_ON_MISSING_CONTRACT" -eq 1 ]]; then
    status=1
  fi
  msg+=("missing contract: $CONTRACT")
else
  python3 - "$CONTRACT" <<'PY' || status=1
import json, sys
path = sys.argv[1]
obj = json.load(open(path, "r", encoding="utf-8"))
required = ["contract_version", "project_type", "quality_gates"]
missing = [k for k in required if k not in obj]
if missing:
    raise SystemExit(f"missing required keys: {missing}")
PY
fi

if [[ ! -f "$PRE_COMMIT" ]]; then
  msg+=("missing pre-commit config: $PRE_COMMIT")
fi

if [[ "$AS_JSON" -eq 1 ]]; then
  python3 - "$status" "$(printf '%s\n' "${msg[@]}")" <<'PY'
import json, sys
status = int(sys.argv[1])
messages = [m for m in sys.argv[2].splitlines() if m.strip()]
print(json.dumps({"ok": status == 0, "messages": messages}, ensure_ascii=False))
PY
else
  if [[ "${#msg[@]}" -gt 0 ]]; then
    for line in "${msg[@]}"; do
      echo "[WARN] $line"
    done
  fi
  if [[ "$status" -eq 0 ]]; then
    echo "[OK] project contract check passed"
  else
    echo "[FAIL] project contract check failed" >&2
  fi
fi
exit "$status"
EOF

  write_utf8_nobom "$governance_dir/codex_crawler_project_init.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROJECT_ROOT=""
FORCE=0
INSTALL_PRE_COMMIT_HOOK=0
SKIP_ENV_EXAMPLE=0
SKIP_README=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --install-pre-commit-hook) INSTALL_PRE_COMMIT_HOOK=1; shift ;;
    --skip-env-example) SKIP_ENV_EXAMPLE=1; shift ;;
    --skip-readme) SKIP_README=1; shift ;;
    *) echo "[WARN] Unknown arg: $1" >&2; shift ;;
  esac
done

[[ -n "$PROJECT_ROOT" ]] || { echo "[ERROR] --project-root is required" >&2; exit 1; }
PROJECT_ROOT="$(python3 -c 'import os,sys;print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$PROJECT_ROOT")"
mkdir -p "$PROJECT_ROOT"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_INIT="$SCRIPT_DIR/codex_project_contract_init.sh"
CRAWLER_TEMPLATE="$SCRIPT_DIR/codex_crawler_contract.template.json"

"$PROJECT_INIT" --project-root "$PROJECT_ROOT" $([[ "$FORCE" -eq 1 ]] && echo --force) $([[ "$INSTALL_PRE_COMMIT_HOOK" -eq 1 ]] && echo --install-pre-commit-hook)

if [[ ! -f "$PROJECT_ROOT/.codex-task-contract.json" || "$FORCE" -eq 1 ]]; then
  cp "$CRAWLER_TEMPLATE" "$PROJECT_ROOT/.codex-task-contract.json"
  echo "[OK] applied crawler contract template"
fi

REQ="$PROJECT_ROOT/requirements.txt"
if [[ ! -f "$REQ" ]]; then
  cat >"$REQ" <<'TXT'
scrapy>=2.11
scrapy-playwright>=0.0.35
TXT
else
  grep -qi '^scrapy' "$REQ" || echo "scrapy>=2.11" >>"$REQ"
  grep -qi '^scrapy-playwright' "$REQ" || echo "scrapy-playwright>=0.0.35" >>"$REQ"
fi
echo "[OK] ensured requirements.txt"

CFG="$PROJECT_ROOT/crawler.config.yaml"
if [[ ! -f "$CFG" || "$FORCE" -eq 1 ]]; then
  cat >"$CFG" <<'YAML'
crawler:
  timeout_seconds: 20
  retries: 4
  retry_backoff_seconds: 1
  concurrency: 8
  download_delay_seconds: 0.5
  respect_robots_txt: true
  resume_enabled: true
  deduplicate_enabled: true
YAML
  echo "[OK] wrote crawler.config.yaml"
fi

if [[ "$SKIP_ENV_EXAMPLE" -eq 0 ]]; then
  ENV_EX="$PROJECT_ROOT/.env.example"
  if [[ ! -f "$ENV_EX" || "$FORCE" -eq 1 ]]; then
    cat >"$ENV_EX" <<'ENV'
HTTP_PROXY=
HTTPS_PROXY=
CRAWLER_OUTPUT=items.jsonl
ENV
    echo "[OK] wrote .env.example"
  fi
fi

if [[ "$SKIP_README" -eq 0 ]]; then
  README="$PROJECT_ROOT/README.md"
  if [[ ! -f "$README" ]]; then
    cat >"$README" <<'MD'
# Crawler Bootstrap Runbook

## Setup
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Basic run
```bash
python3 crawler.py --config crawler.config.yaml
```
MD
  else
    grep -q 'Crawler Bootstrap Runbook' "$README" || cat >>"$README" <<'MD'

## Crawler Bootstrap Runbook
- Use `crawler.config.yaml` for timeout/retry/concurrency.
- Keep outputs append-only in JSONL for resume safety.
MD
  fi
  echo "[OK] ensured README crawler section"
fi

echo "[OK] crawler project initialization complete: $PROJECT_ROOT"
EOF

  write_utf8_nobom "$governance_dir/codex_crawler_smoke_test.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

PROJECT_ROOT=""
AS_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --as-json) AS_JSON=1; shift ;;
    *) echo "[WARN] Unknown arg: $1" >&2; shift ;;
  esac
done

[[ -n "$PROJECT_ROOT" ]] || { echo "[ERROR] --project-root is required" >&2; exit 1; }
PROJECT_ROOT="$(python3 -c 'import os,sys;print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$PROJECT_ROOT")"

checks=()
add() { checks+=("$1|$2|$3"); }

for f in .codex-task-contract.json .pre-commit-config.yaml requirements.txt crawler.config.yaml; do
  if [[ -f "$PROJECT_ROOT/$f" ]]; then
    add "$f" "true" "present"
  else
    add "$f" "false" "missing"
  fi
done

if [[ -f "$PROJECT_ROOT/requirements.txt" ]]; then
  grep -qi '^scrapy' "$PROJECT_ROOT/requirements.txt" && add "requirements_scrapy" "true" "present" || add "requirements_scrapy" "false" "missing scrapy"
  grep -qi '^scrapy-playwright' "$PROJECT_ROOT/requirements.txt" && add "requirements_scrapy_playwright" "true" "present" || add "requirements_scrapy_playwright" "false" "missing scrapy-playwright"
fi

failed=0
for row in "${checks[@]}"; do
  [[ "$(echo "$row" | cut -d'|' -f2)" == "true" ]] || failed=$((failed + 1))
done

if [[ "$AS_JSON" -eq 1 ]]; then
  python3 - "$failed" "$(printf '%s\n' "${checks[@]}")" <<'PY'
import json, sys
failed = int(sys.argv[1])
rows = [r for r in sys.argv[2].splitlines() if r.strip()]
checks = []
for r in rows:
    n,p,d = r.split("|", 2)
    checks.append({"name": n, "pass": p == "true", "detail": d})
print(json.dumps({"ok": failed == 0, "failed": failed, "checks": checks}, ensure_ascii=False))
PY
else
  for row in "${checks[@]}"; do
    n="$(echo "$row" | cut -d'|' -f1)"
    p="$(echo "$row" | cut -d'|' -f2)"
    d="$(echo "$row" | cut -d'|' -f3-)"
    [[ "$p" == "true" ]] && printf '[OK] %s - %s\n' "$n" "$d" || printf '[FAIL] %s - %s\n' "$n" "$d"
  done
fi

[[ "$failed" -eq 0 ]] || exit 1
EOF

  write_utf8_nobom "$governance_dir/README.md" <<'EOF'
# Codex Governance Toolkit (Linux/WSL)

Scripts:
- `codex_preflight_gate.sh`
- `codex_doctor.sh`
- `codex_regression_check.sh`
- `codex_project_contract_init.sh`
- `codex_project_contract_check.sh`
- `codex_task_contract.template.json`
- `codex_crawler_project_init.sh`
- `codex_crawler_smoke_test.sh`
- `codex_crawler_contract.template.json`
- `codex_native_governance_hook.sh`

Use doctor first:
```bash
bash ~/.codex/runtime/governance/codex_doctor.sh
```
EOF

  chmod +x \
    "$governance_dir/codex_preflight_gate.sh" \
    "$governance_dir/codex_doctor.sh" \
    "$governance_dir/codex_regression_check.sh" \
    "$governance_dir/codex_project_contract_init.sh" \
    "$governance_dir/codex_project_contract_check.sh" \
    "$governance_dir/codex_crawler_project_init.sh" \
    "$governance_dir/codex_crawler_smoke_test.sh" \
    "$governance_dir/codex_native_governance_hook.sh"
}

install_global_plugins() {
  local repo_root="$1"
  local workspace="$2"
  local use_symlink="$3"
  local agents_plugins_root="$4"
  local plugins_root="$5"
  local marketplace_path="$6"
  local fetch_command="${7:-mcp-server-fetch}"
  local git_command="${8:-mcp-server-git}"

  local dist_dir="$repo_root/dist/global-plugins"
  local index_path="$dist_dir/index.json"
  [[ -f "$index_path" ]] || die "Missing index.json at $index_path"

  local timestamp backup_root backup_plugins_root
  timestamp="$(date +%Y%m%d-%H%M%S)"
  backup_root="$agents_plugins_root/backup-$timestamp"
  backup_plugins_root="$backup_root/plugins"
  ensure_dir "$plugins_root"
  ensure_dir "$backup_plugins_root"

  if [[ -f "$marketplace_path" ]]; then
    cp "$marketplace_path" "$backup_root/marketplace.json"
  fi

  mapfile -t plugin_names < <(python3 - "$index_path" <<'PY'
import json, sys
obj = json.load(open(sys.argv[1], "r", encoding="utf-8"))
for p in obj.get("plugins", []):
    name = p.get("name")
    if name:
        print(name)
PY
)

  local installed_csv=""
  local name src dst bak
  for name in "${plugin_names[@]}"; do
    src="$dist_dir/$name"
    dst="$plugins_root/$name"
    bak="$backup_plugins_root/$name"
    [[ -d "$src" ]] || die "Plugin source not found: $src"
    if [[ -e "$dst" ]]; then
      mv "$dst" "$bak"
    fi
    if [[ "$use_symlink" == "1" ]]; then
      ln -s "$src" "$dst"
    else
      cp -a "$src" "$dst"
    fi
    if [[ "$name" == "integration-runtime" && -f "$dst/.mcp.json" ]]; then
      python3 - "$dst/.mcp.json" "$workspace" "$fetch_command" "$git_command" <<'PY'
import json, sys
path = sys.argv[1]
workspace = sys.argv[2]
fetch_command = sys.argv[3]
git_command = sys.argv[4]
obj = json.load(open(path, "r", encoding="utf-8"))
srv = obj.get("mcpServers", {})
if isinstance(srv, dict):
    fs = srv.get("filesystem")
    ft = srv.get("fetch")
    gt = srv.get("git")
    if isinstance(fs, dict):
        fs["command"] = "npx"
        fs["args"] = ["-y", "@modelcontextprotocol/server-filesystem", workspace]
    if isinstance(ft, dict):
        ft["command"] = fetch_command
        ft["args"] = []
    if isinstance(gt, dict):
        gt["command"] = git_command
        gt["args"] = ["--repository", workspace]
open(path, "w", encoding="utf-8").write(json.dumps(obj, ensure_ascii=False, indent=2) + "\n")
PY
    fi
    if [[ -z "$installed_csv" ]]; then
      installed_csv="$name"
    else
      installed_csv="$installed_csv,$name"
    fi
  done

  python3 - "$marketplace_path" "$installed_csv" <<'PY'
import json, sys
from pathlib import Path

marketplace_path = Path(sys.argv[1])
installed = [x for x in sys.argv[2].split(",") if x]

if marketplace_path.exists():
    market = json.loads(marketplace_path.read_text(encoding="utf-8"))
else:
    market = {
        "name": "local-global",
        "interface": {"displayName": "Local Global Plugins"},
        "plugins": [],
    }

if not isinstance(market, dict):
    market = {"name": "local-global", "interface": {"displayName": "Local Global Plugins"}, "plugins": []}
if "interface" not in market or not isinstance(market["interface"], dict):
    market["interface"] = {"displayName": "Local Global Plugins"}
if "plugins" not in market or not isinstance(market["plugins"], list):
    market["plugins"] = []

by_name = {p.get("name"): p for p in market["plugins"] if isinstance(p, dict)}
for name in installed:
    rel = f"./plugins/{name}"
    if name not in by_name:
        by_name[name] = {
            "name": name,
            "source": {"source": "local", "path": rel},
            "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"},
            "category": "Developer Tools",
        }
    else:
        p = by_name[name]
        p.setdefault("source", {})
        p.setdefault("policy", {})
        p["source"]["source"] = "local"
        p["source"]["path"] = rel
        p["policy"]["installation"] = "AVAILABLE"
        p["policy"]["authentication"] = "ON_INSTALL"
        p["category"] = "Developer Tools"

market["plugins"] = list(by_name.values())
marketplace_path.parent.mkdir(parents=True, exist_ok=True)
marketplace_path.write_text(json.dumps(market, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

  python3 - "$agents_plugins_root/last-global-install.json" "$backup_root" "$plugins_root" "$marketplace_path" "$workspace" "$installed_csv" <<'PY'
import json, sys
from datetime import datetime
path, backup_root, plugins_root, marketplace_path, workspace, installed = sys.argv[1:]
obj = {
    "installed_at": datetime.now().isoformat(timespec="seconds"),
    "workspace_path": workspace,
    "backup_root": backup_root,
    "plugins_root": plugins_root,
    "marketplace_path": marketplace_path,
    "installed_plugins": [x for x in installed.split(",") if x],
}
open(path, "w", encoding="utf-8").write(json.dumps(obj, ensure_ascii=False, indent=2) + "\n")
PY

  ok "Global plugins installed: $plugins_root"
}

# -------------------------
# Parse arguments
# -------------------------

RepoRoot=""
WorkspacePath=""
SkillsSourcePath=""
DailySmokeTime="09:00"
GitReviewIntervalHours="4"
GitReviewTimeoutSeconds="120"
EnableGitReview="1"
UseSymlink="0"
CodexHome=""
SelfImprovingSourcePath=""
ProactiveSourcePath=""
SuperpowersSourcePath=""
OpenSpaceSourcePath=""
EnableNightlyMemory="1"
NightlyMemoryTime="01:30"
SkipScheduledTasks="0"
SkipCodexConfigSync="0"
SkipSafetyPolicySync="0"
SkipOpenSpaceSync="0"
SkipGovernanceToolkitSync="0"
SkipNativeHooksSync="0"
SkipSubmoduleInit="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) RepoRoot="${2:-}"; shift 2 ;;
    --workspace-path) WorkspacePath="${2:-}"; shift 2 ;;
    --skills-source-path) SkillsSourcePath="${2:-}"; shift 2 ;;
    --daily-smoke-time) DailySmokeTime="${2:-}"; shift 2 ;;
    --git-review-interval-hours) GitReviewIntervalHours="${2:-}"; shift 2 ;;
    --git-review-timeout-seconds) GitReviewTimeoutSeconds="${2:-}"; shift 2 ;;
    --enable-git-review) EnableGitReview="1"; shift ;;
    --disable-git-review) EnableGitReview="0"; shift ;;
    --use-symlink) UseSymlink="1"; shift ;;
    --codex-home) CodexHome="${2:-}"; shift 2 ;;
    --self-improving-source-path) SelfImprovingSourcePath="${2:-}"; shift 2 ;;
    --proactive-source-path) ProactiveSourcePath="${2:-}"; shift 2 ;;
    --superpowers-source-path) SuperpowersSourcePath="${2:-}"; shift 2 ;;
    --openspace-source-path) OpenSpaceSourcePath="${2:-}"; shift 2 ;;
    --enable-nightly-memory) EnableNightlyMemory="1"; shift ;;
    --disable-nightly-memory) EnableNightlyMemory="0"; shift ;;
    --nightly-memory-time) NightlyMemoryTime="${2:-}"; shift 2 ;;
    --skip-scheduled-tasks) SkipScheduledTasks="1"; shift ;;
    --skip-codex-config-sync) SkipCodexConfigSync="1"; shift ;;
    --skip-safety-policy-sync) SkipSafetyPolicySync="1"; shift ;;
    --skip-openspace-sync) SkipOpenSpaceSync="1"; shift ;;
    --skip-governance-toolkit-sync) SkipGovernanceToolkitSync="1"; shift ;;
    --skip-native-hooks-sync) SkipNativeHooksSync="1"; shift ;;
    --skip-submodule-init) SkipSubmoduleInit="1"; shift ;;
    -h|--help) show_help; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

require_cmd python3
require_cmd git
require_cmd node
require_cmd npx
BootstrapScriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$RepoRoot" ]]; then
  RepoRoot="$(first_existing_path "$BootstrapScriptDir/../common/claude-code-main" "$BootstrapScriptDir/../claude-code-main")"
  [[ -n "$RepoRoot" ]] && info "Auto-detected RepoRoot: $RepoRoot"
fi
if [[ -z "$WorkspacePath" ]]; then
  if [[ -n "${CODEX_WORKSPACE_PATH:-}" ]]; then
    WorkspacePath="$CODEX_WORKSPACE_PATH"
  elif [[ -n "${CODEX_WORKSPACE:-}" ]]; then
    WorkspacePath="$CODEX_WORKSPACE"
  elif [[ -f "$HOME/.agents/active-repo.txt" ]]; then
    WorkspacePath="$(head -n 1 "$HOME/.agents/active-repo.txt" | tr -d '\r' || true)"
  fi
  if [[ -z "$WorkspacePath" ]]; then
    WorkspacePath="$HOME/codex-workspace"
  fi
  info "Auto-resolved WorkspacePath: $WorkspacePath"
fi

RepoRoot="$(resolve_path "$RepoRoot")"
WorkspacePath="$(resolve_path "$WorkspacePath")"
SkillsSourcePath="$(resolve_path "$SkillsSourcePath")"
CodexHome="$(resolve_path "${CodexHome:-$HOME/.codex}")"
SelfImprovingSourcePath="$(resolve_path "$SelfImprovingSourcePath")"
ProactiveSourcePath="$(resolve_path "$ProactiveSourcePath")"
SuperpowersSourcePath="$(resolve_path "$SuperpowersSourcePath")"
OpenSpaceSourcePath="$(resolve_path "$OpenSpaceSourcePath")"

if [[ -z "$RepoRoot" || ! -d "$RepoRoot" ]]; then
  die "RepoRoot not found. Pass --repo-root explicitly or keep standard bundle layout (common/claude-code-main)."
fi

repoParent="$(dirname "$RepoRoot")"
bundleRoot="$repoParent"
if [[ "$(basename "$repoParent" | tr '[:upper:]' '[:lower:]')" == "common" ]]; then
  bundleRoot="$(dirname "$repoParent")"
fi

try_init_submodules_if_needed "$bundleRoot" "$SkipSubmoduleInit" \
  "$bundleRoot/external/modules/mod-a" \
  "$bundleRoot/external/modules/mod-b" \
  "$bundleRoot/external/modules/mod-c" \
  "$bundleRoot/external/modules/mod-d"

if [[ -z "$SuperpowersSourcePath" ]]; then
  SuperpowersSourcePath="$(first_existing_path "$bundleRoot/external/modules/mod-a" "$bundleRoot/mod-a")"
  [[ -n "$SuperpowersSourcePath" ]] && info "Auto-enabled superpowers source: $SuperpowersSourcePath"
fi
if [[ -z "$OpenSpaceSourcePath" ]]; then
  OpenSpaceSourcePath="$(first_existing_path "$bundleRoot/external/modules/mod-b" "$bundleRoot/mod-b")"
  [[ -n "$OpenSpaceSourcePath" ]] && info "Auto-enabled OpenSpace source: $OpenSpaceSourcePath"
fi
if [[ -z "$SelfImprovingSourcePath" ]]; then
  SelfImprovingSourcePath="$(first_existing_path "$bundleRoot/external/modules/mod-c" "$bundleRoot/mod-c")"
  [[ -n "$SelfImprovingSourcePath" ]] && info "Auto-enabled self-improving source: $SelfImprovingSourcePath"
fi
if [[ -z "$ProactiveSourcePath" ]]; then
  ProactiveSourcePath="$(first_existing_path "$bundleRoot/external/modules/mod-d" "$bundleRoot/mod-d")"
  [[ -n "$ProactiveSourcePath" ]] && info "Auto-enabled proactive source: $ProactiveSourcePath"
fi

ensure_dir "$WorkspacePath"
info "Git review automation: $( [[ "$EnableGitReview" == "1" ]] && echo enabled || echo disabled )"
info "Nightly memory automation: $( [[ "$EnableNightlyMemory" == "1" ]] && echo enabled || echo disabled )"

if [[ -n "$SkillsSourcePath" && ! -d "$SkillsSourcePath" ]]; then
  die "SkillsSourcePath not found: $SkillsSourcePath"
fi
if [[ -n "$SuperpowersSourcePath" && ! -d "$SuperpowersSourcePath" ]]; then
  die "SuperpowersSourcePath not found: $SuperpowersSourcePath"
fi
if [[ -n "$SuperpowersSourcePath" && ! -d "$SuperpowersSourcePath/skills" ]]; then
  die "Superpowers skills folder missing: $SuperpowersSourcePath/skills"
fi
if [[ -n "$SelfImprovingSourcePath" && ! -d "$SelfImprovingSourcePath" ]]; then
  die "SelfImprovingSourcePath not found: $SelfImprovingSourcePath"
fi
if [[ -n "$ProactiveSourcePath" && ! -d "$ProactiveSourcePath" ]]; then
  die "ProactiveSourcePath not found: $ProactiveSourcePath"
fi
if [[ -n "$OpenSpaceSourcePath" && ! -d "$OpenSpaceSourcePath" ]]; then
  die "OpenSpaceSourcePath not found: $OpenSpaceSourcePath"
fi
if [[ -n "$OpenSpaceSourcePath" && ! -d "$OpenSpaceSourcePath/openspace/host_skills/skill-discovery" ]]; then
  die "OpenSpace host skill missing: $OpenSpaceSourcePath/openspace/host_skills/skill-discovery"
fi
if [[ -n "$OpenSpaceSourcePath" && ! -d "$OpenSpaceSourcePath/openspace/host_skills/delegate-task" ]]; then
  die "OpenSpace host skill missing: $OpenSpaceSourcePath/openspace/host_skills/delegate-task"
fi

agentsRoot="${HOME}/.agents"
agentsPluginsRoot="$agentsRoot/plugins"
globalPluginsDir="$agentsPluginsRoot/plugins"
globalMarketplacePath="$agentsPluginsRoot/marketplace.json"
globalSkillsDir="$agentsRoot/skills"
globalAutomationDir="$agentsRoot/automation"

codexMemoriesDir="$CodexHome/memories"
codexRuntimeDir="$CodexHome/runtime"
codexGovernanceDir="$codexRuntimeDir/governance"
codexProactiveDir="$codexRuntimeDir/proactive"
codexConfigPath="$CodexHome/config.toml"
codexRulesDir="$CodexHome/rules"
codexRulesPath="$codexRulesDir/default.rules"
codexAgentsPath="$CodexHome/AGENTS.md"
codexHooksConfigPath="$CodexHome/hooks.json"
codexSelfImprovingDir="$CodexHome/self-improving-for-codex"
codexSelfImprovingScriptsDir="$codexSelfImprovingDir/scripts"

codexSuperpowersDir="$CodexHome/superpowers"
codexOpenSpaceDir="$CodexHome/openspace"
globalSuperpowersSkillLink="$globalSkillsDir/superpowers"
globalOpenSpaceSkillDiscoveryDir="$globalSkillsDir/openspace-skill-discovery"
globalOpenSpaceDelegateTaskDir="$globalSkillsDir/openspace-delegate-task"

ensure_dir "$agentsRoot"
ensure_dir "$agentsPluginsRoot"
ensure_dir "$globalPluginsDir"
ensure_dir "$globalSkillsDir"
ensure_dir "$globalAutomationDir"
ensure_dir "$CodexHome"
ensure_dir "$codexMemoriesDir"
ensure_dir "$codexRuntimeDir"
ensure_dir "$codexRulesDir"
ensure_dir "$codexProactiveDir"
ensure_dir "$codexSelfImprovingScriptsDir"

fetchCommand="mcp-server-fetch"
gitCommand="mcp-server-git"
globalToolsVenv="$CodexHome/venvs/global-tools"
globalToolsPython="$globalToolsVenv/bin/python"
globalFetchBin="$globalToolsVenv/bin/mcp-server-fetch"
globalGitBin="$globalToolsVenv/bin/mcp-server-git"

step "Bootstrap MCP python runtimes (fetch/git)"
if [[ ! -x "$globalToolsPython" ]]; then
  if python3 -m venv "$globalToolsVenv" >/dev/null 2>&1; then
    ok "Created MCP tools venv: $globalToolsVenv"
  else
    warn "Failed to create MCP tools venv: $globalToolsVenv (fallback to PATH/system python)"
  fi
fi
if [[ -x "$globalToolsPython" ]]; then
  if "$globalToolsPython" -m pip install --disable-pip-version-check mcp-server-fetch mcp-server-git >/dev/null 2>&1; then
    ok "MCP python runtimes installed in venv: mcp-server-fetch, mcp-server-git"
  else
    warn "Failed to install MCP python runtimes in venv (fallback to PATH/system python)"
  fi
fi
if [[ -x "$globalFetchBin" ]]; then
  fetchCommand="$globalFetchBin"
fi
if [[ -x "$globalGitBin" ]]; then
  gitCommand="$globalGitBin"
fi
info "Resolved fetch command: $fetchCommand"
info "Resolved git command: $gitCommand"

step "Installing global plugins"
install_global_plugins "$RepoRoot" "$WorkspacePath" "$UseSymlink" "$agentsPluginsRoot" "$globalPluginsDir" "$globalMarketplacePath" "$fetchCommand" "$gitCommand"

step "Syncing global automation scripts (if provided)"
automation_source=""
if [[ -d "$RepoRoot/.agents/automation/scripts" ]]; then
  automation_source="$RepoRoot/.agents/automation/scripts"
elif [[ -d "$BootstrapScriptDir/automation/scripts" ]]; then
  automation_source="$BootstrapScriptDir/automation/scripts"
fi
if [[ -n "$automation_source" ]]; then
  sync_dir_mirror "$automation_source" "$globalAutomationDir/scripts" "automation"
  if [[ -f "$(dirname "$automation_source")/README.md" ]]; then
    cp -f "$(dirname "$automation_source")/README.md" "$globalAutomationDir/README.md"
  fi
  if [[ -f "$(dirname "$automation_source")/.env.example" ]]; then
    cp -f "$(dirname "$automation_source")/.env.example" "$globalAutomationDir/.env.example"
  fi
  ok "Automation scripts synced from: $automation_source"
  ok "Automation target: $globalAutomationDir/scripts"
else
  warn "Automation scripts folder not found. checked: $RepoRoot/.agents/automation/scripts and $BootstrapScriptDir/automation/scripts"
fi

secret_setup_script="$globalAutomationDir/scripts/setup_wsl_secret_service.sh"
if [[ -x "$secret_setup_script" ]]; then
  step "Attempting keyring/secret-service quick init (non-blocking)"
  if bash "$secret_setup_script" --no-install-deps --no-shell-config >/dev/null 2>&1; then
    ok "WSL secret-service quick init completed."
  else
    warn "WSL secret-service quick init skipped/failed; run setup_wsl_secret_service.sh manually if keyring warnings persist."
  fi
fi

step "Syncing user skills (optional)"
if [[ -n "$SkillsSourcePath" ]]; then
  sync_dir_mirror "$SkillsSourcePath" "$globalSkillsDir" "skills"
  ok "Skills synced: $globalSkillsDir"
else
  info "SkillsSourcePath not provided; skip skill sync."
fi

step "Bootstrap pre-commit runtime"
if ! command -v pre-commit >/dev/null 2>&1; then
  preCommitBin="$globalToolsVenv/bin/pre-commit"
  if [[ -x "$globalToolsPython" ]]; then
    if "$globalToolsPython" -m pip install --disable-pip-version-check pre-commit >/dev/null 2>&1; then
      ensure_dir "$HOME/.local/bin"
      ln -sfn "$preCommitBin" "$HOME/.local/bin/pre-commit" || true
      export PATH="$HOME/.local/bin:$PATH"
    else
      warn "pre-commit install failed in MCP tools venv (non-blocking)"
    fi
  else
    python3 -m pip install --user pre-commit >/dev/null 2>&1 || warn "pre-commit install failed (non-blocking)"
  fi
fi
if command -v pre-commit >/dev/null 2>&1; then
  ok "pre-commit available: $(pre-commit --version)"
else
  warn "pre-commit is still unavailable."
fi

step "Syncing superpowers (optional)"
if [[ -n "$SuperpowersSourcePath" ]]; then
  sync_dir_mirror "$SuperpowersSourcePath" "$codexSuperpowersDir" "superpowers"
  ensure_symlink "$globalSuperpowersSkillLink" "$codexSuperpowersDir/skills"
  ok "Superpowers linked: $globalSuperpowersSkillLink -> $codexSuperpowersDir/skills"
else
  info "SuperpowersSourcePath not provided; skip superpowers sync."
fi

step "Syncing OpenSpace (optional)"
openSpaceMcpWorkspace=""
openSpaceMcpHostSkillDirs=""
if [[ "$SkipOpenSpaceSync" == "0" && -n "$OpenSpaceSourcePath" ]]; then
  sync_dir_mirror "$OpenSpaceSourcePath" "$codexOpenSpaceDir" "openspace"
  sync_dir_mirror "$codexOpenSpaceDir/openspace/host_skills/skill-discovery" "$globalOpenSpaceSkillDiscoveryDir" "openspace-skill-discovery"
  sync_dir_mirror "$codexOpenSpaceDir/openspace/host_skills/delegate-task" "$globalOpenSpaceDelegateTaskDir" "openspace-delegate-task"
  openSpaceMcpWorkspace="$codexOpenSpaceDir"
  openSpaceMcpHostSkillDirs="$globalOpenSpaceSkillDiscoveryDir,$globalOpenSpaceDelegateTaskDir,$globalSkillsDir"
  ok "OpenSpace host skills synced."
elif [[ "$SkipOpenSpaceSync" == "1" ]]; then
  info "SkipOpenSpaceSync enabled; skip OpenSpace sync."
else
  info "OpenSpaceSourcePath not provided; skip OpenSpace sync."
fi

step "Initializing global memory/proactive runtime"
ensure_file "$codexMemoriesDir/PROFILE.md" $'# PROFILE\n'
ensure_file "$codexMemoriesDir/ACTIVE.md" $'# ACTIVE\n'
ensure_file "$codexMemoriesDir/LEARNINGS.md" $'# LEARNINGS\n'
ensure_file "$codexMemoriesDir/ERRORS.md" $'# ERRORS\n'
ensure_file "$codexMemoriesDir/FEATURE_REQUESTS.md" $'# FEATURE_REQUESTS\n'
ensure_file "$codexMemoriesDir/AUDIT_LOG.jsonl" ''
ensure_file "$codexProactiveDir/context-recovery-latest.md" $'# Context Recovery\n'
ensure_file "$codexProactiveDir/heartbeat-latest.json" '{}\n'
ensure_file "$codexProactiveDir/writeback-queue.md" $'# Writeback Queue\n'
ensure_file "$codexProactiveDir/writeback-queue.jsonl" ''

step "Syncing self-improving assets (optional)"
if [[ -n "$SelfImprovingSourcePath" ]]; then
  if [[ -d "$SelfImprovingSourcePath/scripts" ]]; then
    sync_dir_mirror "$SelfImprovingSourcePath/scripts" "$codexSelfImprovingScriptsDir" "self-improving-scripts"
    ok "Self-improving scripts synced: $SelfImprovingSourcePath/scripts -> $codexSelfImprovingScriptsDir"
  else
    warn "Self-improving scripts folder missing: $SelfImprovingSourcePath/scripts"
  fi
  for name in README.md SKILL.md; do
    if [[ -f "$SelfImprovingSourcePath/$name" ]]; then
      cp -f "$SelfImprovingSourcePath/$name" "$codexSelfImprovingDir/$name"
    fi
  done
else
  info "SelfImprovingSourcePath not provided; using base memory scaffold only."
fi

step "Syncing proactive metadata (optional)"
if [[ -n "$ProactiveSourcePath" ]]; then
  write_utf8_nobom "$codexProactiveDir/source-note.md" <<EOF
# Proactive Source

- Source path: $ProactiveSourcePath
- Imported at: $(date -Iseconds)
- Strategy: fuse reusable proactive behavior into one global Codex system.
EOF
  ok "Proactive source note updated: $codexProactiveDir/source-note.md"
else
  info "ProactiveSourcePath not provided; proactive source note skipped."
fi

if [[ "$SkipCodexConfigSync" == "0" ]]; then
  step "Syncing ~/.codex/config.toml"
  ensure_codex_config_mcp "$codexConfigPath" "$WorkspacePath" "$openSpaceMcpWorkspace" "$openSpaceMcpHostSkillDirs" "$fetchCommand" "$gitCommand"
  ok "Codex config synced: $codexConfigPath"
else
  info "SkipCodexConfigSync enabled; skip config.toml sync."
fi

if [[ "$SkipSafetyPolicySync" == "0" ]]; then
  step "Syncing global safety rules"
  ensure_marked_block "$codexRulesPath" "# codex-global-delete-guard:start" "# codex-global-delete-guard:end" <<'EOF'
# codex-global-delete-guard:start
prefix_rule(
    pattern = ["rm"],
    decision = "prompt",
    justification = "Any deletion command must require confirmation."
)
prefix_rule(
    pattern = ["del"],
    decision = "prompt",
    justification = "Any Windows delete command must require confirmation."
)
prefix_rule(
    pattern = ["rmdir"],
    decision = "prompt",
    justification = "Directory deletion must require confirmation."
)
prefix_rule(
    pattern = ["powershell", "Remove-Item"],
    decision = "prompt",
    justification = "PowerShell deletion must require confirmation."
)
prefix_rule(
    pattern = ["cmd", "/c", "del"],
    decision = "prompt",
    justification = "cmd deletion must require confirmation."
)
# codex-global-delete-guard:end
EOF
  ensure_marked_block "$codexRulesPath" "# codex-global-risk-guard:start" "# codex-global-risk-guard:end" <<'EOF'
# codex-global-risk-guard:start
prefix_rule(
    pattern = ["git", "reset", "--hard"],
    decision = "prompt",
    justification = "Hard reset is destructive and must require confirmation."
)
prefix_rule(
    pattern = ["git", "clean", "-fd"],
    decision = "prompt",
    justification = "Cleaning untracked files is destructive and must require confirmation."
)
# codex-global-risk-guard:end
EOF
  ok "Safety policy synced: $codexRulesPath"
else
  info "SkipSafetyPolicySync enabled; skip default.rules sync."
fi

step "Syncing AGENTS / ACTIVE policy blocks"
append_block_if_missing "$codexAgentsPath" "codex-global-safety-guard:start" <<'EOF'
<!-- codex-global-safety-guard:start -->
Global safety rules:
- Allow create/edit/rename only within the current project scope.
- Never delete files/directories unless explicitly confirmed by user.
- Never delete files outside the current project scope.
- If task involves cleanup/reset/remove/overwrite/bulk move, explain impact scope first.
<!-- codex-global-safety-guard:end -->
EOF

append_block_if_missing "$codexAgentsPath" "codex-global-execution-policy:start" <<'EOF'
<!-- codex-global-execution-policy:start -->
Continuous Execution Policy (Global):
- Continue by default until completion or real blocker.
- Do not ask "whether to continue" after each micro-step.
- Ask user only for destructive actions, permission blockers, major architecture tradeoffs, or missing critical requirements.
<!-- codex-global-execution-policy:end -->
EOF

append_block_if_missing "$codexAgentsPath" "codex-global-ml-active-trigger:start" <<'EOF'
<!-- codex-global-ml-active-trigger:start -->
ML/DL Active Trigger Policy (Global):
- Trigger based on semantic intent + concrete evidence, not keyword-only matching.
- If classified as ML/DL, use diagnosis-first mode before large code edits.
- If evidence is insufficient, fallback to generic workflow with minimal validation.
<!-- codex-global-ml-active-trigger:end -->
EOF

append_block_if_missing "$codexAgentsPath" "codex-global-reliability-policy:start" <<'EOF'
<!-- codex-global-reliability-policy:start -->
AI Coding Reliability Policy (Global):
- Treat failure handling as first-class requirement.
- Define timeout/retry/backoff for external calls.
- Ensure state-changing writes are atomic or recoverable.
- Avoid unbounded queues/loops/memory growth without limits.
- Run at least one failure-oriented validation for risky changes.
<!-- codex-global-reliability-policy:end -->
EOF

append_block_if_missing "$codexAgentsPath" "codex-global-governance-policy:start" <<'EOF'
<!-- codex-global-governance-policy:start -->
Policy Enforcement Levels (Global):
- block: hard stop for clear safety/reliability risk.
- warn: continue allowed, but must provide mitigation in output.
- advise: recommendation only.
Profiles:
- light / standard / strict selected by semantic intent + risk evidence.
<!-- codex-global-governance-policy:end -->
EOF

append_block_if_missing "$codexAgentsPath" "codex-global-policy-runtime:start" <<EOF
<!-- codex-global-policy-runtime:start -->
Runtime policy enforcement (global):
- Use runtime scripts under $codexGovernanceDir.
- Preflight: bash "$codexGovernanceDir/codex_preflight_gate.sh" --task-text "<task>" --command-line "<cmd>"
- Doctor: bash "$codexGovernanceDir/codex_doctor.sh" --codex-home "$CodexHome"
- Regression: bash "$codexGovernanceDir/codex_regression_check.sh" --codex-home "$CodexHome"
<!-- codex-global-policy-runtime:end -->
EOF

append_block_if_missing "$codexMemoriesDir/ACTIVE.md" "codex-active-execution-policy:start" <<'EOF'
<!-- codex-active-execution-policy:start -->
## Execution Policy (Global)
- Continue normal tasks by default until done or truly blocked.
- Ask user only for destructive actions or hard blockers.
<!-- codex-active-execution-policy:end -->
EOF

append_block_if_missing "$codexMemoriesDir/ACTIVE.md" "codex-active-reliability-policy:start" <<'EOF'
<!-- codex-active-reliability-policy:start -->
## Reliability Policy (Global)
- For risky changes, include failure map + failure-oriented validation.
- Keep external calls bounded (timeout/retry/backoff).
<!-- codex-active-reliability-policy:end -->
EOF

append_block_if_missing "$codexMemoriesDir/ACTIVE.md" "codex-active-governance-policy:start" <<'EOF'
<!-- codex-active-governance-policy:start -->
## Governance Policy (Global)
- Enforce block/warn/advise by task risk.
- Use strict profile for high-risk domains.
<!-- codex-active-governance-policy:end -->
EOF

append_block_if_missing "$codexMemoriesDir/ACTIVE.md" "codex-active-policy-runtime:start" <<'EOF'
<!-- codex-active-policy-runtime:start -->
## Runtime Governance (Global)
- Keep governance toolkit scripts under ~/.codex/runtime/governance.
- Run doctor after bootstrap and regression before team handoff.
<!-- codex-active-policy-runtime:end -->
EOF

if [[ "$SkipGovernanceToolkitSync" == "0" ]]; then
  step "Installing governance toolkit scripts"
  ensure_governance_toolkit_scripts "$codexGovernanceDir"
  ok "Governance toolkit synced: $codexGovernanceDir"
else
  info "SkipGovernanceToolkitSync enabled; skip governance toolkit sync."
fi

if [[ "$SkipNativeHooksSync" == "0" ]]; then
  step "Syncing native hooks config"
  ensure_native_hooks_config "$codexHooksConfigPath" "$codexGovernanceDir/codex_native_governance_hook.sh"
  ok "Hooks config synced: $codexHooksConfigPath"
else
  info "SkipNativeHooksSync enabled; skip hooks.json sync."
fi

if [[ "$SkipScheduledTasks" == "0" ]]; then
  step "Configuring cron jobs (Linux/WSL scheduled tasks)"
  hour="${DailySmokeTime%:*}"
  minute="${DailySmokeTime#*:}"
  add_or_update_cron_job "Codex-Auto-Daily-Smoke" "$minute $hour * * *" "bash \"$codexGovernanceDir/codex_doctor.sh\" --codex-home \"$CodexHome\" >/tmp/codex_daily_smoke.log 2>&1"

  if [[ "$EnableGitReview" == "1" ]]; then
    add_or_update_cron_job "Codex-Auto-Git-Review" "0 */$GitReviewIntervalHours * * *" "echo \"git-review placeholder timeout=$GitReviewTimeoutSeconds\" >/tmp/codex_git_review.log 2>&1"
  fi

  if [[ "$EnableNightlyMemory" == "1" ]]; then
    nh="${NightlyMemoryTime%:*}"
    nm="${NightlyMemoryTime#*:}"
    if [[ -f "$codexSelfImprovingScriptsDir/run_night_memory_pipeline.py" ]]; then
      add_or_update_cron_job "Codex-Auto-Nightly-Memory" "$nm $nh * * *" "python3 \"$codexSelfImprovingScriptsDir/run_night_memory_pipeline.py\" --apply --main-memory-dir \"$CodexHome/memories\" --bridge-memory-dir \"$CodexHome/memories\" --lock-dir \"$CodexHome/runtime/locks\" --status-path \"$CodexHome/runtime/night-memory-pipeline/last_run.json\" >/tmp/codex_nightly_memory.log 2>&1"
    else
      warn "Nightly memory enabled but run_night_memory_pipeline.py not found under $codexSelfImprovingScriptsDir; skipped cron registration."
    fi
  fi
else
  info "SkipScheduledTasks enabled; skip cron setup."
fi

step "Final verification"
[[ -f "$codexConfigPath" ]] && info "Codex config: $codexConfigPath"
[[ -f "$codexRulesPath" ]] && info "Codex rules: $codexRulesPath"
[[ -f "$codexAgentsPath" ]] && info "Codex AGENTS: $codexAgentsPath"
[[ -f "$codexHooksConfigPath" ]] && info "Codex hooks: $codexHooksConfigPath"
[[ -d "$globalPluginsDir" ]] && info "Plugins dir: $globalPluginsDir"
[[ -d "$globalSkillsDir" ]] && info "Skills dir: $globalSkillsDir"
[[ -d "$codexGovernanceDir" ]] && info "Governance dir: $codexGovernanceDir"

if [[ -x "$codexGovernanceDir/codex_doctor.sh" ]]; then
  step "Running governance doctor"
  if bash "$codexGovernanceDir/codex_doctor.sh" --codex-home "$CodexHome"; then
    ok "Governance doctor passed."
  else
    warn "Governance doctor reported failures."
  fi
fi

ok "Full Linux/WSL bootstrap completed."
