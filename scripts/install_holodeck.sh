#!/usr/bin/env bash
# Install holodeck-gw from PyPI with container-side fixes for upstream packaging gaps.
#
# - Stale cython<3 metadata: build with the venv toolchain (--no-build-isolation).
# - cyutils.pyx calls long() removed in Python 3.12+.
set -euo pipefail

REQ_FILE="${1:-/tmp/req-pulsar.txt}"
VIRTUAL_ENV="${VIRTUAL_ENV:-/opt/venvs/pta}"
pip="${VIRTUAL_ENV}/bin/pip"
python="${VIRTUAL_ENV}/bin/python"

line="$(grep '^holodeck-gw==' "$REQ_FILE")"
version="${line#holodeck-gw==}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

url="$("$python" - <<PY
import json
import urllib.request

data = json.load(urllib.request.urlopen(f"https://pypi.org/pypi/holodeck-gw/${version}/json"))
print(next(u["url"] for u in data["urls"] if u["packagetype"] == "sdist"))
PY
)"

curl -fsSL -o holodeck.tar.gz "$url"
tar -xzf holodeck.tar.gz
src="holodeck-gw-${version}"

sed -i 's/long(normal_threshold)/int(normal_threshold)/' "${src}/holodeck/cyutils.pyx"

"$pip" install --no-build-isolation "${src}/"
