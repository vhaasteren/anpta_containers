#!/usr/bin/env bash
set -euo pipefail

: "${SOFTWARE_DIR:?}"
: "${VIRTUAL_ENV:?}"

# Dockerfile sets TEMPO2=${SOFTWARE_DIR}/tempo2/T2runtime; fall back if unset.
TEMPO2="${TEMPO2:-${SOFTWARE_DIR}/tempo2/T2runtime}"
CLOCK_DST="${TEMPO2}/clock"
CLOCK_SRC="${SOFTWARE_DIR}/pulsar-clock-corrections/T2runtime/clock"
mkdir -p "${CLOCK_DST}"
cd "${SOFTWARE_DIR}"
if [ ! -d pulsar-clock-corrections ]; then
  git clone --depth=1 https://github.com/ipta/pulsar-clock-corrections.git
fi
cd pulsar-clock-corrections
mkdir -p gh-pages/.this_is_gh_pages
for year in $(seq 2022 $(( $(date +%Y) - 1 ))); do
  cp T2runtime/clock/tai2tt_bipm2019.clk "T2runtime/clock/tai2tt_bipm${year}.clk"
done
"${VIRTUAL_ENV}/bin/python" ./update_clock_corrections.py --gh-pages ./gh-pages

# Install the updated Tempo2-format clocks where Tempo2 actually reads them.
# Merge (not replace): keep Tempo2-only files that the IPTA tree does not ship
# (e.g. coe2utc.clk, time_ao.dat), overwrite/extend everything else, and add
# new site files such as gmrt2gps.clk.
cp -a "${CLOCK_SRC}/." "${CLOCK_DST}/"

# EPTA-specific overlays (must run after the merge so they win).
wget -q -O "${CLOCK_DST}/ncyobs2obspm.clk" \
  https://gitlab.in2p3.fr/epta/epta-dr2/-/raw/master/EPTA-DR2/clockfiles/ncyobs2obspm.clk
wget -q -O "${CLOCK_DST}/tai2tt_bipm2020.clk" \
  https://gitlab.in2p3.fr/epta/epta-dr2/-/raw/master/EPTA-DR2/clockfiles/tai2tt_bipm2020.clk
wget -q -O "${CLOCK_DST}/tai2tt_bipm2021.clk" \
  https://gitlab.in2p3.fr/epta/epta-dr2/-/raw/master/EPTA-DR2/clockfiles/tai2tt_bipm2021.clk
After rebuilding the image (or running this once as root in a live container), a quick check:

cmp -s "$TEMPO2/clock/ao2gps.clk" \
       /opt/software/pulsar-clock-corrections/T2runtime/clock/ao2gps.clk \
  && echo "ao2gps installed" || echo "ao2gps still stale"
test -f "$TEMPO2/clock/gmrt2gps.clk" && echo "gmrt present"
