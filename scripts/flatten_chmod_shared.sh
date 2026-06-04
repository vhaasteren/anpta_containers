#!/usr/bin/env bash
# Flatten directory trees that span many overlay layers, then chmod for shared access.
# In-place chmod -R on a multi-layer venv triggers slow overlayfs copy-up on cluster storage.
set -euo pipefail

flatten_chmod_one() {
  local tree="$1"
  [[ -e "$tree" ]] || { echo "flatten_chmod_shared: missing path: $tree" >&2; return 1; }
  local tmp="${tree}.flat.$$"
  rm -rf "$tmp"
  cp -a "$tree" "$tmp"
  rm -rf "$tree"
  mv "$tmp" "$tree"
  chmod -R a+rwX "$tree"
}

for tree in "$@"; do
  flatten_chmod_one "$tree"
done
