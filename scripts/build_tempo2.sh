#!/usr/bin/env bash
set -euo pipefail

: "${SOFTWARE_DIR:?}"
: "${CALCEPH:?}"

cd "${SOFTWARE_DIR}"
git clone --depth=1 https://bitbucket.org/psrsoft/tempo2.git
cd tempo2
sync && perl -pi -e 's/chmod \+x/#chmod +x/' bootstrap
./bootstrap

X11LIB="/usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
./configure --x-libraries="${X11LIB}" --with-calceph="${CALCEPH}/install/lib" --enable-shared --enable-static --with-pic \
    CPPFLAGS="-I${CALCEPH}/install/include"

make -j"$(nproc)"
make install
make plugins-install
make clean
rm -rf .git





