#!/usr/bin/env python3
"""Patch pyvela for Python 3.11 (Ubuntu 22.04 GPU images).

Vela.jl v0.1.5 uses dict subscripts with double quotes inside f-strings that use
double quotes, e.g. f"...{model["PSR"]}...". That requires PEP 701 (Python 3.12+).
Ubuntu 24.04 / CPU images use 3.12; CUDA 12.4 on Ubuntu 22.04 uses 3.11.

Rewrite all ["key"] subscripts to ['key'] under site-packages/pyvela/ (safe on
3.11 and 3.12). Must not import pyvela — import would load broken syntax first.
"""
from __future__ import annotations

import os
import pathlib
import re
import sys

# Matches one level of ["..."]; run in a loop for nested ["input"]["file"].
_SUBSCRIPT = re.compile(r'\["([^"]+)"\]')


def pyvela_package_dir() -> pathlib.Path:
    venv = pathlib.Path(os.environ.get("VIRTUAL_ENV", "/opt/venvs/pta"))
    matches = sorted(venv.glob("lib/python*/site-packages/pyvela"))
    if not matches:
        sys.exit(f"patch_pyvela_priors: could not find pyvela under {venv}")
    return matches[0]


def patch_file(path: pathlib.Path) -> int:
    text = path.read_text(encoding="utf-8")
    total = 0
    while True:
        new_text, n = _SUBSCRIPT.subn(lambda m: f"['{m.group(1)}']", text)
        if n == 0:
            break
        total += n
        text = new_text
    if total:
        path.write_text(text, encoding="utf-8")
    return total


def main() -> None:
    pkg = pyvela_package_dir()
    grand_total = 0
    files_patched = 0
    for path in sorted(pkg.rglob("*.py")):
        n = patch_file(path)
        if n:
            files_patched += 1
            grand_total += n
            print(f"patch_pyvela_priors: {path.relative_to(pkg)}: {n} subscript(s)", file=sys.stderr)

    if grand_total == 0:
        print(f"patch_pyvela_priors: no changes needed under {pkg}", file=sys.stderr)
    else:
        print(
            f"patch_pyvela_priors: patched {grand_total} subscript(s) in {files_patched} file(s)",
            file=sys.stderr,
        )


if __name__ == "__main__":
    main()
