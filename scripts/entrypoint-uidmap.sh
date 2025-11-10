#!/usr/bin/env bash

set -euo pipefail

USERNAME="${USERNAME:-anpta}"
HOME_DIR="/home/${USERNAME}"
VENV="${VIRTUAL_ENV:-/opt/venvs/pta}"

HOST_UID="${HOST_UID:-}"
HOST_GID="${HOST_GID:-}"

# === UID/GID remap (only if root and IDs provided) ===
if [ "$(id -u)" = "0" ] && [ -n "$HOST_UID" ] && [ -n "$HOST_GID" ]; then
  # Group
  existing_group="$(getent group "$HOST_GID" | cut -d: -f1 || true)"
  if [ -n "$existing_group" ] && [ "$existing_group" != "$USERNAME" ]; then
    usermod -g "$existing_group" "$USERNAME"
  else
    current_gid="$(getent group "$USERNAME" | cut -d: -f3 || true)"
    if [ "${current_gid:-}" != "$HOST_GID" ]; then
      groupmod -g "$HOST_GID" "$USERNAME" || true
    fi
  fi

  # User UID
  current_uid="$(id -u "$USERNAME")"
  if [ "$current_uid" != "$HOST_UID" ]; then
    usermod -o -u "$HOST_UID" "$USERNAME" || true
  fi

  # Fix /home/anpta ownership
  mkdir -p "$HOME_DIR"
  chown -R "$HOST_UID:$HOST_GID" "$HOME_DIR"
fi

# === HOME override ===
HOME_OVERRIDE="${HOME_OVERRIDE:-$HOME_DIR}"
mkdir -p "$HOME_OVERRIDE"
if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
  chown -R "$HOST_UID:$HOST_GID" "$HOME_OVERRIDE" 2>/dev/null || true
fi
export HOME="$HOME_OVERRIDE"

# === User-writable pip installs (outside system venv) ===
export PYTHONUSERBASE="${PYTHONUSERBASE:-$HOME/.pyuser}"
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-$HOME/.pycache}"
mkdir -p "$PYTHONUSERBASE/bin" "$PYTHONUSERBASE/lib" "$PYTHONPYCACHEPREFIX"
if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
  chown -R "$HOST_UID:$HOST_GID" "$PYTHONUSERBASE" "$PYTHONPYCACHEPREFIX" 2>/dev/null || true
fi
case ":$PATH:" in *":$PYTHONUSERBASE/bin:"*) ;; *) export PATH="$PYTHONUSERBASE/bin:$PATH";; esac

# pip config: install to user prefix
mkdir -p "$HOME/.config/pip"
cat > "$HOME/.config/pip/pip.conf" <<EOF
[global]
prefix = $PYTHONUSERBASE
no-warn-script-location = true
EOF
chown -R "$HOST_UID:$HOST_GID" "$HOME/.config" 2>/dev/null || true

# === .pth shim: make user installs visible in venv ===
PYVER="$(python - <<'PY'
import sys
print(f"{sys.version_info[0]}.{sys.version_info[1]}")
PY
)"

VENV_SITE="$VIRTUAL_ENV/lib/python${PYVER}/site-packages"
mkdir -p "$VENV_SITE"
cat > "$VENV_SITE/pta-user-prefix.pth" <<PTH
import os, sys
p = os.environ.get("PYTHONUSERBASE")
if p:
    sp = os.path.join(p, "lib", f"python{sys.version_info[0]}.{sys.version_info[1]}", "site-packages")
    if os.path.isdir(sp) and sp not in sys.path:
        sys.path.insert(0, sp)
PTH

# Optional: allow writes to system venv
if [ "${VENV_WRITABLE:-0}" = "1" ] && [ -d "$VENV" ]; then
  SP="$VENV/lib/python${PYVER}/site-packages"
  if [ -d "$SP" ]; then
    echo "VENV_WRITABLE=1: enabling writes to system venv"
    chown -R "$HOST_UID:$HOST_GID" "$SP" 2>/dev/null || true
  fi
fi

# Drop privileges
exec gosu "$USERNAME" "$@"
