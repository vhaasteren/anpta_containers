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

# Determine the runtime UID/GID for the target user (after any remap)
TARGET_UID="$(id -u "$USERNAME")"
TARGET_GID="$(id -g "$USERNAME")"

# === HOME override (devcontainers set HOME_OVERRIDE) ===
HOME_OVERRIDE="${HOME_OVERRIDE:-$HOME_DIR}"
mkdir -p "$HOME_OVERRIDE"
if [ "$(id -u)" = "0" ]; then
  chown -R "$TARGET_UID:$TARGET_GID" "$HOME_OVERRIDE" 2>/dev/null || true
fi
export HOME="$HOME_OVERRIDE"

# === User-writable pip installs (standard: under $HOME) ===
export PYTHONUSERBASE="${PYTHONUSERBASE:-$HOME/.local}"
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-$HOME/.cache/pycache}"
mkdir -p "$PYTHONUSERBASE/bin" "$PYTHONPYCACHEPREFIX"
if [ "$(id -u)" = "0" ]; then
  chown -R "$TARGET_UID:$TARGET_GID" "$PYTHONUSERBASE" "$PYTHONPYCACHEPREFIX" 2>/dev/null || true
fi

# Ensure the container venv always wins for tooling (python/jupyter/ipython).
# This avoids VSCode/Jupyter picking up user-base executables by accident.
#
# Normalize PATH: remove any existing occurrences of venv + user bin so we can re-prepend in order.
PATH=":${PATH}:"
PATH="${PATH//:${VENV}/bin:/:}"
PATH="${PATH//:${PYTHONUSERBASE}/bin:/:}"
PATH="${PATH#:}"
PATH="${PATH%:}"
export PATH="${VENV}/bin:${PYTHONUSERBASE}/bin:${PATH}"

# pip config:
# - Default: do NOT force user-prefix installs; pip in the venv should install into the venv (DoD).
# - Optional: set PIP_USE_USERBASE=1 to force user-prefix installs under $PYTHONUSERBASE.
if [ "${PIP_USE_USERBASE:-0}" = "1" ]; then
  mkdir -p "$HOME/.config/pip"
  cat > "$HOME/.config/pip/pip.conf" <<EOF
[global]
prefix = $PYTHONUSERBASE
no-warn-script-location = true
EOF
  if [ "$(id -u)" = "0" ]; then
    chown -R "$TARGET_UID:$TARGET_GID" "$HOME/.config" 2>/dev/null || true
  fi
fi

# === sitecustomize: make user installs visible in venv ===
PYVER="$(python - <<'PY'
import sys
print(f"{sys.version_info[0]}.{sys.version_info[1]}")
PY
)"

VENV_SITE="$VIRTUAL_ENV/lib/python${PYVER}/site-packages"
mkdir -p "$VENV_SITE"
cat > "$VENV_SITE/sitecustomize.py" <<'PY'
import os, sys, site

def _add_user_site():
    # Prefer explicit PYTHONUSERBASE if set; otherwise fall back to $HOME/.local
    base = os.environ.get("PYTHONUSERBASE")
    if not base:
        base = os.path.join(os.path.expanduser("~"), ".local")
    sp = os.path.join(
        base,
        "lib",
        f"python{sys.version_info[0]}.{sys.version_info[1]}",
        "site-packages",
    )
    if os.path.isdir(sp):
        # Use addsitedir so .pth files (editable installs) are processed
        site.addsitedir(sp)

_add_user_site()
PY

# Also add user site via usercustomize to cover cases where a system sitecustomize shadows ours
cat > "$VENV_SITE/usercustomize.py" <<'PY'
import os, sys, site

def _user_site():
    base = os.environ.get("PYTHONUSERBASE")
    if not base:
        base = os.path.join(os.path.expanduser("~"), ".local")
    return os.path.join(
        base,
        "lib",
        f"python{sys.version_info[0]}.{sys.version_info[1]}",
        "site-packages",
    )

sp = _user_site()
if os.path.isdir(sp):
    site.addsitedir(sp)
PY

# Optional: allow writes to system venv
if [ "${VENV_WRITABLE:-0}" = "1" ] && [ -d "$VENV" ] && [ "$(id -u)" = "0" ]; then
  SP="$VENV/lib/python${PYVER}/site-packages"
  if [ -d "$SP" ]; then
    echo "VENV_WRITABLE=1: enabling writes to system venv"
    chown -R "$TARGET_UID:$TARGET_GID" "$SP" 2>/dev/null || true
  fi
fi

# Drop privileges
exec gosu "$USERNAME" "$@"
