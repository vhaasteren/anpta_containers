#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <docker-archive.tar> <output.sif> [tmp_base_dir]" >&2
  echo "- tmp_base_dir (optional): directory on a large filesystem to use for tmp/cache/session/work." >&2
  echo "Example: $0 /work/user/singularity_images/anpta_gpu_image.tar /work/user/singularity_images/anpta_gpu.sif /work/user/singularity_images" >&2
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 2 ]; then
  usage
  exit 1
fi

IN_TAR="$1"
OUT_SIF="$2"
TMP_BASE_ARG="${3:-}"

if [ ! -f "$IN_TAR" ]; then
  echo "Error: input docker-archive tar not found: $IN_TAR" >&2
  exit 1
fi

# Resolve absolute paths without relying on realpath
abspath() {
  local p="$1"
  if [ -d "$p" ]; then
    (cd "$p" && pwd -P)
  else
    local d
    d="$(cd "$(dirname "$p")" && pwd -P)"
    echo "$d/$(basename "$p")"
  fi
}

IN_TAR_ABS="$(abspath "$IN_TAR")"
OUT_SIF_ABS="$(abspath "$OUT_SIF")"
OUT_DIR_ABS="$(dirname "$OUT_SIF_ABS")"

mkdir -p "$OUT_DIR_ABS"

# Choose a large filesystem for tmp/cache/session/work.
# Priority: explicit arg > existing env > co-locate under output directory.
TMP_BASE="${TMP_BASE_ARG:-${APPTAINER_TMPDIR:-${SINGULARITY_TMPDIR:-${TMPDIR:-}}}}"
if [ -z "$TMP_BASE" ]; then
  TMP_BASE="$OUT_DIR_ABS/.apptainer"
fi

TMPDIR_USE="$TMP_BASE/tmp"
CACHEDIR_USE="$TMP_BASE/cache"
SESSIONDIR_USE="$TMP_BASE/session"
WORKDIR_USE="$TMP_BASE/work"
mkdir -p "$TMPDIR_USE" "$CACHEDIR_USE" "$SESSIONDIR_USE" "$WORKDIR_USE"

export APPTAINER_TMPDIR="$TMPDIR_USE"
export SINGULARITY_TMPDIR="$TMPDIR_USE"
export TMPDIR="$TMPDIR_USE"
export APPTAINER_CACHEDIR="$CACHEDIR_USE"
export SINGULARITY_CACHEDIR="$CACHEDIR_USE"
export APPTAINER_SESSIONDIR="$SESSIONDIR_USE"
export SINGULARITY_SESSIONDIR="$SESSIONDIR_USE"
export APPTAINER_WORKDIR="$WORKDIR_USE"
export SINGULARITY_WORKDIR="$WORKDIR_USE"

# Select runner
if command -v apptainer >/dev/null 2>&1; then
  RUNNER="apptainer"
elif command -v singularity >/dev/null 2>&1; then
  RUNNER="singularity"
else
  echo "Error: neither 'apptainer' nor 'singularity' found in PATH" >&2
  exit 1
fi

# Ensure docker-archive:// prefix
if [[ "$IN_TAR_ABS" == docker-archive://* ]]; then
  SRC="$IN_TAR_ABS"
else
  SRC="docker-archive://$IN_TAR_ABS"
fi

# Detect flags supported for the chosen runner
TMPDIR_FLAG=""
if "$RUNNER" build --help 2>&1 | grep -q -- "--tmpdir"; then
  TMPDIR_FLAG="--tmpdir"
fi

echo "Using $RUNNER"
echo "TMPDIR=$TMPDIR_USE"
echo "CACHE=$CACHEDIR_USE"
echo "SESSIONDIR=$SESSIONDIR_USE"
echo "WORKDIR=$WORKDIR_USE"
echo "Building: $OUT_SIF_ABS <- $IN_TAR_ABS"

set -x
# Step 1: build to a sandbox on the large filesystem to avoid small local session dirs
SANDBOX_DIR="$(mktemp -d -p "$TMP_BASE" sandbox-XXXXXX)"
trap 'rc=$?; set +e; [ -n "$SANDBOX_DIR" ] && rm -rf "$SANDBOX_DIR"; exit $rc' EXIT

if [ -n "$TMPDIR_FLAG" ]; then
  "$RUNNER" build "$TMPDIR_FLAG" "$TMPDIR_USE" --sandbox "$SANDBOX_DIR" "$SRC"
else
  "$RUNNER" build --sandbox "$SANDBOX_DIR" "$SRC"
fi

# Step 2: pack sandbox into a SIF on the large filesystem
if [ -n "$TMPDIR_FLAG" ]; then
  "$RUNNER" build "$TMPDIR_FLAG" "$TMPDIR_USE" "$OUT_SIF_ABS" "$SANDBOX_DIR"
else
  "$RUNNER" build "$OUT_SIF_ABS" "$SANDBOX_DIR"
fi
set +x

echo "Build complete: $OUT_SIF_ABS"


