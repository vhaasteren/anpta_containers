#!/usr/bin/env bash
set -euo pipefail

: "${SOFTWARE_DIR:?}"
: "${VIRTUAL_ENV:?}"

# Requires: HEALPix (optional), CALCEPH, TEMPO2, PGPLOT env, numpy present in venv

cd "${SOFTWARE_DIR}"
# Original: git clone --depth=1 git://git.code.sf.net/p/psrchive/code psrchive
# Temporary: Using vhaasteren's GitHub fork with healpix branch that includes the epsic submodule fix
git clone --depth=1 -b healpix https://github.com/vhaasteren/psrchive.git psrchive
cd psrchive
./bootstrap

# Ensure numpy headers are available to the build
"${VIRTUAL_ENV}/bin/python" -c "import numpy; import sys; print('Using numpy', numpy.__version__, 'from', numpy.get_include(), file=sys.stderr)"

./configure \
  --prefix="${SOFTWARE_DIR}/psrchive/install" \
  --enable-shared \
  --enable-python \
  --with-python-sys-prefix \
  PYTHON="${VIRTUAL_ENV}/bin/python3"

make -j"$(nproc)"
make check
make install
make -C More/python install
make clean

