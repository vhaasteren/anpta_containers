#!/usr/bin/env bash
set -euo pipefail

: "${JULIAUP_DEPOT_PATH:?}"
: "${JULIA_DEPOT_PATH:?}"
: "${JULIA_PROJECT:?}"
: "${VIRTUAL_ENV:?}"

JULIAUP_BIN="${JULIAUP_DEPOT_PATH}/bin/juliaup"
JULIA_BIN="${JULIAUP_DEPOT_PATH}/bin/julia"

mkdir -p /opt/julia "${JULIA_DEPOT_PATH}" "${JULIA_PROJECT}"

if [ ! -x "${JULIA_BIN}" ]; then
  rm -rf "${JULIAUP_DEPOT_PATH}"
  curl -fsSL https://install.julialang.org | sh -s -- --yes --path "${JULIAUP_DEPOT_PATH}"
  export PATH="${JULIAUP_DEPOT_PATH}/bin:${PATH}"
  "${JULIAUP_BIN}" add 1.11
  "${JULIAUP_BIN}" default 1.11
fi

export PATH="${JULIAUP_DEPOT_PATH}/bin:${PATH}"
export JULIA_CONDAPKG_BACKEND=Null
export JULIA_CPU_TARGET=generic

"${JULIA_BIN}" /usr/local/bin/install_vela.jl

export JUPYTER_DATA_DIR="${VIRTUAL_ENV}/share/jupyter"
export JUPYTER="${VIRTUAL_ENV}/bin/jupyter"
"${JULIA_BIN}" --project="${JULIA_PROJECT}" -e \
  'using IJulia; IJulia.installkernel("Julia (vela)", "--project='"${JULIA_PROJECT}"'")'

"${JULIA_BIN}" --project="${JULIA_PROJECT}" -e 'using Vela; println("Vela smoke test: ", Vela)'

bash /usr/local/bin/flatten_chmod_shared.sh /opt/julia
