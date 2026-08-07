#!/usr/bin/env bash
set -euo pipefail

: "${SOFTWARE_DIR:?}"

# Dockerfile sets TEMPO2=${SOFTWARE_DIR}/tempo2/T2runtime; fall back if unset.
TEMPO2="${TEMPO2:-${SOFTWARE_DIR}/tempo2/T2runtime}"
CLOCK_DST="${TEMPO2}/clock"
CLOCK_REPO="${SOFTWARE_DIR}/pulsar-clock-corrections"
CLOCK_SRC="${CLOCK_REPO}/T2runtime/clock"

mkdir -p "${CLOCK_DST}"

repo_git() {
  git -c "safe.directory=${CLOCK_REPO}" -C "${CLOCK_REPO}" "$@"
}

# Install the latest accepted IPTA clock snapshot. If a checkout is already
# present (for example in an existing image layer), refresh it and discard any
# files synthesized by older versions of this script.
if [ ! -e "${CLOCK_REPO}" ]; then
  git clone --depth=1 \
    https://github.com/ipta/pulsar-clock-corrections.git \
    "${CLOCK_REPO}"
elif [ -d "${CLOCK_REPO}/.git" ]; then
  repo_git fetch --depth=1 origin main
  repo_git reset --hard FETCH_HEAD
else
  echo "Clock repository path exists but is not a Git checkout: ${CLOCK_REPO}" >&2
  exit 1
fi

# Guard against the historical workaround that copied TT(BIPM2019) under
# newer realization names before those files were available upstream. Validate
# the source snapshot before changing the live Tempo2 clock directory.
for year in 2020 2021 2022 2023 2024 2025; do
  clock_file="${CLOCK_SRC}/tai2tt_bipm${year}.clk"
  if ! grep -Fqx "# TAI TT(BIPM${year})" "${clock_file}"; then
    echo "Incorrect or missing TT(BIPM${year}) clock: ${clock_file}" >&2
    exit 1
  fi
done

for year in 2022 2023 2024 2025; do
  if cmp -s \
    "${CLOCK_SRC}/tai2tt_bipm2019.clk" \
    "${CLOCK_SRC}/tai2tt_bipm${year}.clk"; then
    echo "TT(BIPM${year}) is unexpectedly identical to TT(BIPM2019)" >&2
    exit 1
  fi
done

# Install the updated Tempo2-format clocks where Tempo2 actually reads them.
# Merge (not replace): keep Tempo2-only files that the IPTA tree does not ship
# (e.g. coe2utc.clk, time_ao.dat), overwrite/extend everything else, and add
# new site files such as gmrt2gps.clk.
cp -a "${CLOCK_SRC}/." "${CLOCK_DST}/"

# Curated PINT override: Tempo2-format .clk from T2runtime, Tempo-format
# time_*.dat from tempo/clock. Do not reuse Tempo2's retained time_*.dat —
# those can be wrongly ordered / stale, and PINT_CLOCK_OVERRIDE would prefer them.
PINT_CLOCK_DST="${SOFTWARE_DIR}/pint-clock-override"
TEMPO_CLOCK_SRC="${CLOCK_REPO}/tempo/clock"

rm -rf "${PINT_CLOCK_DST}"
mkdir -p "${PINT_CLOCK_DST}"

shopt -s nullglob
clk_files=("${CLOCK_SRC}"/*.clk)
dat_files=("${TEMPO_CLOCK_SRC}"/time_*.dat)
if [ "${#clk_files[@]}" -eq 0 ]; then
  echo "No Tempo2 .clk files in ${CLOCK_SRC}" >&2
  exit 1
fi
if [ "${#dat_files[@]}" -eq 0 ]; then
  echo "No Tempo time_*.dat files in ${TEMPO_CLOCK_SRC}" >&2
  exit 1
fi
cp -a "${clk_files[@]}" "${PINT_CLOCK_DST}/"
cp -a "${dat_files[@]}" "${PINT_CLOCK_DST}/"
shopt -u nullglob

if [ -f "${CLOCK_SRC}/leap.sec" ]; then
  cp -a "${CLOCK_SRC}/leap.sec" "${PINT_CLOCK_DST}/"
fi

# Curated IPTA-DR3 / EPTA overlay (COPY clockfiles/ → dr3-clock-overlay).
# Selective install only — never blind-copy the whole DR3/EPTA dump.
DR3_CLOCKS="${SOFTWARE_DIR}/dr3-clock-overlay"
if [ ! -d "${DR3_CLOCKS}" ]; then
  echo "DR3 clock overlay directory missing: ${DR3_CLOCKS}" >&2
  exit 1
fi

# Site stubs fill gaps only. Never overwrite a file already present from the
# public IPTA snapshot (once upstream ships real corrections, those win).
DR3_STUBS=(
  fast2gps.clk
  lofar2gps.clk
  nenufar2gps.clk
  eflfrhba2gps.clk
  julfrhba2gps.clk
  ndlfrhba2gps.clk
  polfrhba2gps.clk
  tblfrhba2gps.clk
  uwlfrhba2gps.clk
  time_fast.dat
)
for f in "${DR3_STUBS[@]}"; do
  src="${DR3_CLOCKS}/${f}"
  for dst_dir in "${CLOCK_DST}" "${PINT_CLOCK_DST}"; do
    if [ ! -f "${dst_dir}/${f}" ]; then
      if [ ! -f "${src}" ]; then
        echo "Missing DR3 clock ${f} (needed in ${dst_dir}, not in public IPTA)" >&2
        exit 1
      fi
      cp -a "${src}" "${dst_dir}/"
    fi
  done
done

# Asterix tip (ipta/pulsar-clock-corrections#38): force-replace only.
if [ ! -f "${DR3_CLOCKS}/effix2gps.clk" ]; then
  echo "Missing required EPTA effix2gps.clk in ${DR3_CLOCKS}" >&2
  exit 1
fi
cp -a "${DR3_CLOCKS}/effix2gps.clk" "${CLOCK_DST}/"
cp -a "${DR3_CLOCKS}/effix2gps.clk" "${PINT_CLOCK_DST}/"

if [ -f "${DR3_CLOCKS}/effedd2gps.clk" ]; then
  cp -a "${DR3_CLOCKS}/effedd2gps.clk" "${CLOCK_DST}/"
  cp -a "${DR3_CLOCKS}/effedd2gps.clk" "${PINT_CLOCK_DST}/"
fi

# Final tree must contain every DR3-required clock (public and/or overlay).
DR3_REQUIRED=("${DR3_STUBS[@]}" effix2gps.clk)
for f in "${DR3_REQUIRED[@]}"; do
  for dst_dir in "${CLOCK_DST}" "${PINT_CLOCK_DST}"; do
    if [ ! -f "${dst_dir}/${f}" ]; then
      echo "Required clock missing after merge: ${dst_dir}/${f}" >&2
      exit 1
    fi
  done
done

effix_tip="$(
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      if ($1 ~ /^[+-]?[0-9]+(\.[0-9]+)?$/) {
        mjd = $1 + 0
        if (mjd > tip) tip = mjd
      }
    }
    END {
      if (tip == "") exit 1
      printf "%.6f\n", tip
    }
  ' "${CLOCK_DST}/effix2gps.clk"
)"
if awk -v tip="${effix_tip}" 'BEGIN { exit !(tip > 59294.5) }'; then
  :
else
  echo "effix2gps.clk tip MJD ${effix_tip} is not past public IPTA freeze (59294.5)" >&2
  exit 1
fi

# Leave an auditable record of the exact clock snapshot installed in the image.
repo_git rev-parse HEAD \
  > "${SOFTWARE_DIR}/CLOCK_CORRECTIONS_REVISION"
ls -1 "${DR3_CLOCKS}" \
  > "${SOFTWARE_DIR}/DR3_CLOCK_OVERLAY_MANIFEST"
