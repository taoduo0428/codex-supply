#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

install_deps=1
configure_shell=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-install-deps) install_deps=0; shift ;;
    --no-shell-config) configure_shell=0; shift ;;
    *) printf '[ERROR] Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

step() { printf '[STEP] %s\n' "$1"; }
ok() { printf '[OK] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1" >&2; }
fail() { printf '[FAIL] %s\n' "$1" >&2; }

is_wsl=false
if [[ -n "${WSL_DISTRO_NAME:-}" || -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
  is_wsl=true
fi
if [[ "$is_wsl" != true ]]; then
  warn 'This script is intended for WSL/Linux. Continuing anyway.'
fi

need_install=false
for cmd in gnome-keyring-daemon secret-tool dbus-send; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    need_install=true
    warn "Missing dependency: $cmd"
  fi
done

if [[ "$need_install" == true && "$install_deps" -eq 1 ]]; then
  step 'Installing keyring dependencies (gnome-keyring, libsecret-tools, dbus-user-session)'
  if ! command -v apt-get >/dev/null 2>&1; then
    fail 'apt-get not found. Install packages manually for your distro.'
    exit 2
  fi

  install_cmd='apt-get update && apt-get install -y gnome-keyring libsecret-tools dbus-user-session dbus-x11'
  if [[ "$(id -u)" -eq 0 ]]; then
    bash -lc "$install_cmd"
  elif sudo -n true >/dev/null 2>&1; then
    sudo bash -lc "$install_cmd"
  else
    fail 'Need sudo privilege to install keyring packages.'
    printf 'Run this manually:\n'
    printf '  sudo apt-get update && sudo apt-get install -y gnome-keyring libsecret-tools dbus-user-session dbus-x11\n'
    exit 2
  fi
fi

for cmd in gnome-keyring-daemon secret-tool dbus-send; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "Dependency still missing: $cmd"
    exit 2
  fi
done
ok 'Keyring dependencies are present.'

init_script="$HOME/.config/codex/secret-service-init.sh"
mkdir -p "$(dirname "$init_script")"
cat > "$init_script" <<'EOF'
#!/usr/bin/env bash
# Ensure DBus session and gnome-keyring secrets service are available in WSL shells.

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && command -v dbus-launch >/dev/null 2>&1; then
  # shellcheck disable=SC2046
  eval "$(dbus-launch --sh-syntax 2>/dev/null)" >/dev/null 2>&1 || true
fi

if command -v gnome-keyring-daemon >/dev/null 2>&1; then
  if ! dbus-send --session --dest=org.freedesktop.secrets --type=method_call /org/freedesktop/secrets org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; then
    # shellcheck disable=SC2046
    eval "$(gnome-keyring-daemon --start --components=secrets 2>/dev/null)" >/dev/null 2>&1 || true
  fi
fi
EOF
chmod +x "$init_script"
ok "Wrote init script: $init_script"

ensure_rc_block() {
  local file="$1"
  local start_marker="$2"
  local end_marker="$3"
  local block_file="$4"
  python3 - "$file" "$start_marker" "$end_marker" "$block_file" <<'PY'
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
}

if [[ "$configure_shell" -eq 1 ]]; then
  block_tmp="$(mktemp)"
  cat > "$block_tmp" <<'EOF'
# >>> codex-secret-service:start >>>
if [ -f "$HOME/.config/codex/secret-service-init.sh" ]; then
  . "$HOME/.config/codex/secret-service-init.sh"
fi
# <<< codex-secret-service:end <<<
EOF
  ensure_rc_block "$HOME/.bashrc" "# >>> codex-secret-service:start >>>" "# <<< codex-secret-service:end <<<" "$block_tmp"
  if [[ -f "$HOME/.zshrc" ]]; then
    ensure_rc_block "$HOME/.zshrc" "# >>> codex-secret-service:start >>>" "# <<< codex-secret-service:end <<<" "$block_tmp"
  fi
  rm -f "$block_tmp"
  ok 'Shell startup config updated (~/.bashrc and existing ~/.zshrc).'
fi

# Activate for current shell.
# shellcheck disable=SC1090
source "$init_script" || true

if dbus-send --session --dest=org.freedesktop.secrets --type=method_call /org/freedesktop/secrets org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; then
  ok 'Secret-service is active in current shell.'
  printf '[INFO] Reopen terminal (or run: source ~/.bashrc) to apply for new shells.\n'
  exit 0
fi

warn 'Secret-service is still not active in current shell.'
printf '[INFO] Try running: source ~/.bashrc\n'
printf '[INFO] If still failing, ensure gnome-keyring is installed and no shell policy blocks dbus-launch.\n'
exit 1
