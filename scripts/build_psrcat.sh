#!/usr/bin/env bash
set -euo pipefail

: "${SOFTWARE_DIR:?}"

cd "${SOFTWARE_DIR}"
wget -q https://www.atnf.csiro.au/research/pulsar/psrcat/downloads/psrcat_pkg.v1.68.tar.gz
tar -xzf psrcat_pkg.v1.68.tar.gz
rm -f psrcat_pkg.v1.68.tar.gz
cd "${SOFTWARE_DIR}/psrcat_tar"
/bin/bash makeit





