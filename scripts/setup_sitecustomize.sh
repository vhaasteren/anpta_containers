#!/usr/bin/env bash
set -euo pipefail

: "${VIRTUAL_ENV:?}"

# Get Python version from the venv
PYVER=$("${VIRTUAL_ENV}/bin/python" -c "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')")

# Add user site hook to system sitecustomize (runs for all Python invocations, not just venv)
# This ensures user-installed packages (via PYTHONUSERBASE or ~/.local) are always visible
cat >> "/etc/python${PYVER}/sitecustomize.py" <<'PY'
import os, sys, site

def _add_user_site():
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
        site.addsitedir(sp)

_add_user_site()
PY




