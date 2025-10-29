#!/usr/bin/env bash
set -euo pipefail

: "${SOFTWARE_DIR:?}"
: "${VIRTUAL_ENV:?}"

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

wget -q -O "${SOFTWARE_DIR}/tempo2/T2runtime/clock/ncyobs2obspm.clk" https://gitlab.in2p3.fr/epta/epta-dr2/-/raw/master/EPTA-DR2/clockfiles/ncyobs2obspm.clk
wget -q -O "${SOFTWARE_DIR}/tempo2/T2runtime/clock/tai2tt_bipm2020.clk" https://gitlab.in2p3.fr/epta/epta-dr2/-/raw/master/EPTA-DR2/clockfiles/tai2tt_bipm2020.clk
wget -q -O "${SOFTWARE_DIR}/tempo2/T2runtime/clock/tai2tt_bipm2021.clk" https://gitlab.in2p3.fr/epta/epta-dr2/-/raw/master/EPTA-DR2/clockfiles/tai2tt_bipm2021.clk


