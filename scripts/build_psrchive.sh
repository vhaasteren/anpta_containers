#!/usr/bin/env bash
set -euo pipefail

: "${SOFTWARE_DIR:?}"
: "${VIRTUAL_ENV:?}"

# Requires: HEALPix (optional), CALCEPH, TEMPO2, PGPLOT env, numpy present in venv

cd "${SOFTWARE_DIR}"
git clone --depth=1 git://git.code.sf.net/p/psrchive/code psrchive
cd psrchive
./bootstrap

# Ensure numpy headers are available to the build
"${VIRTUAL_ENV}/bin/python" -c "import numpy; import sys; print('Using numpy', numpy.__version__, 'from', numpy.get_include(), file=sys.stderr)"

./configure \
  --enable-shared \
  --enable-python \
  --with-python-sys-prefix \
  PYTHON="${VIRTUAL_ENV}/bin/python3" \
  CPPFLAGS="-I${CALCEPH}/install/include -I${TEMPO2}/include ${CPPFLAGS:-}" \
  LDFLAGS="-L${CALCEPH}/install/lib -L${TEMPO2}/lib ${LDFLAGS:-}"

make -j"$(nproc)"
make check
make install
make -C More/python install

cd ..
rm -rf psrchive


