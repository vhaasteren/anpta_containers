#!/usr/bin/env bash
set -euo pipefail

: "${SOFTWARE_DIR:?}"

CALCEPH_DIR="${SOFTWARE_DIR}/calceph-3.5.3"
export CALCEPH="${CALCEPH_DIR}"

cd "${SOFTWARE_DIR}"
wget -q https://www.imcce.fr/content/medias/recherche/equipes/asd/calceph/calceph-3.5.3.tar.gz
tar -xzf calceph-3.5.3.tar.gz
rm -f calceph-3.5.3.tar.gz
cd "${CALCEPH_DIR}"
./configure --prefix="${CALCEPH_DIR}/install" --with-pic --enable-shared --enable-static --enable-fortran --enable-thread
make -j"$(nproc)"
make check
make install
make clean





