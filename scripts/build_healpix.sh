#!/usr/bin/env bash
set -euo pipefail

: "${SOFTWARE_DIR:?}"
: "${HEALPIX:?}"
: "${HEALPIX_DIR:?}"

mkdir -p "${HEALPIX}"
cd "${HEALPIX}"
wget -qO healpix.tgz "https://downloads.sourceforge.net/project/healpix/Healpix_3.82/healpix_cxx-3.82.0.tar.gz"
tar -xzf healpix.tgz --strip-components=1
./configure --prefix="${HEALPIX_DIR}" --with-cfitsio=/usr/local
make -j"$(nproc)"
make install
make clean
rm -f healpix.tgz





