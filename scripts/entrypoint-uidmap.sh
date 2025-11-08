#!/usr/bin/env bash
set -euo pipefail

USERNAME="${USERNAME:-anpta}"
HOME_DIR="/home/${USERNAME}"
VENV="${VIRTUAL_ENV:-/opt/venvs/pta}"

HOST_UID="${HOST_UID:-}"
HOST_GID="${HOST_GID:-}"

# Only run remap if root AND both ids provided
if [ "$(id -u)" = "0" ] && [ -n "$HOST_UID" ] && [ -n "$HOST_GID" ]; then
  # --- Group: reuse existing or remap 'anpta' group ---
  existing_group="$(getent group "$HOST_GID" | cut -d: -f1 || true)"
  if [ -n "$existing_group" ] && [ "$existing_group" != "$USERNAME" ]; then
    usermod -g "$existing_group" "$USERNAME"
  else
    current_gid="$(getent group "$USERNAME" | cut -d: -f3 || true)"
    if [ "${current_gid:-}" != "$HOST_GID" ]; then
      groupmod -g "$HOST_GID" "$USERNAME" || true
    fi
  fi

  # --- User: remap UID (allow non-unique) ---
  current_uid="$(id -u "$USERNAME")"
  if [ "$current_uid" != "$HOST_UID" ]; then
    usermod -o -u "$HOST_UID" "$USERNAME" || true
  fi

  # --- HOME: ensure exists and is owned (small tree) ---
  mkdir -p "$HOME_DIR"
  chown -R "$HOST_UID:$HOST_GID" "$HOME_DIR"
fi

# === FAST PATH: do not chown the system venv ===
# Redirect installs & caches into the workspace (or $HOME)
export PYTHONUSERBASE="${PYTHONUSERBASE:-/work/.pyuser}"
export PYTHONPYCACHEPREFIX="${PYTHONPYCACHEPREFIX:-/work/.pycache}"

# Ensure the user base/bin is on PATH
USER_BIN="$PYTHONUSERBASE/bin"
case ":$PATH:" in
  *":$USER_BIN:"*) : ;;
  *) export PATH="$USER_BIN:$PATH" ;;
esac

# Compute user site-packages path for current interpreter
PYVER="$(python - <<'PY'
import sys
print(f"{sys.version_info[0]}.{sys.version_info[1]}")
PY
)"

USER_SITE="$PYTHONUSERBASE/lib/python${PYVER}/site-packages"

# Make dirs; chown only if we have mapped IDs
mkdir -p "$USER_BIN" "$USER_SITE" "$PYTHONPYCACHEPREFIX"
if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
  chown -R "$HOST_UID:$HOST_GID" "$PYTHONUSERBASE" "$PYTHONPYCACHEPREFIX" 2>/dev/null || true
fi

# Ensure site-packages is importable
export PYTHONPATH="$USER_SITE${PYTHONPATH:+:$PYTHONPATH}"

# Create a per-user pip config that defaults to installing into the workspace prefix
PIP_CFG="$HOME_DIR/.config/pip/pip.conf"
mkdir -p "$(dirname "$PIP_CFG")"
cat > "$PIP_CFG" <<EOF
[global]
prefix = $PYTHONUSERBASE
no-warn-script-location = true
EOF
# Ensure pip config is owned by the user if we have mapped IDs
if [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
  chown -R "$HOST_UID:$HOST_GID" "$HOME_DIR/.config" 2>/dev/null || true
fi

# Optional: allow opt-in venv writes for rare workflows
if [ "${VENV_WRITABLE:-0}" = "1" ] && [ -d "$VENV" ]; then
  SP="$VENV/lib/python${PYVER}/site-packages"
  if [ -d "$SP" ]; then
    echo "VENV_WRITABLE=1: enabling writes to system venv (slower)"
    chown -R --from=0:0 "$HOST_UID:$HOST_GID" "$SP" 2>/dev/null || \
      chown -R "$HOST_UID:$HOST_GID" "$SP"
  fi
fi

# Always set HOME coherently for the target user
export HOME="$HOME_DIR"

# Drop privileges
exec gosu "$USERNAME" "$@"
