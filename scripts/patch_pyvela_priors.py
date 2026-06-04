#!/usr/bin/env python3
"""Patch pyvela priors.py for Python <3.12.

Vela.jl v0.1.5 uses nested double quotes inside an f-string in priors.py, which
requires PEP 701 (Python 3.12+). Ubuntu 22.04 GPU bases only provide Python 3.11.
Replace dict access with single-quoted keys so the module parses on 3.11.
"""
from __future__ import annotations

import pathlib
import sys

import pyvela

PRIORS = pathlib.Path(pyvela.__file__).resolve().parent / "priors.py"
NEEDLE = 'prior_info["distribution"]'
REPLACEMENT = "prior_info['distribution']"


def main() -> None:
    text = PRIORS.read_text(encoding="utf-8")
    if NEEDLE not in text:
        if REPLACEMENT in text:
            print(f"patch_pyvela_priors: already patched ({PRIORS})", file=sys.stderr)
            return
        sys.exit(f"patch_pyvela_priors: pattern not found in {PRIORS}")

    count = text.count(NEEDLE)
    PRIORS.write_text(text.replace(NEEDLE, REPLACEMENT), encoding="utf-8")
    print(f"patch_pyvela_priors: patched {count} occurrence(s) in {PRIORS}", file=sys.stderr)


if __name__ == "__main__":
    main()
