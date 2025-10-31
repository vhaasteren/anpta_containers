#!/usr/bin/env bash
set -euo pipefail

: "${VIRTUAL_ENV:?}"

# Install enterprise_outliers with patched setup.py to use libgomp instead of libiomp5
git clone --branch main --depth=1 https://github.com/nanograv/enterprise_outliers /tmp/enterprise_outliers
cd /tmp/enterprise_outliers
sed -i 's/-liomp5/-lgomp/' setup.py
${VIRTUAL_ENV}/bin/pip install --no-build-isolation .
rm -rf /tmp/enterprise_outliers

