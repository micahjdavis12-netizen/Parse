#!/bin/sh
set -eu

product="${BUILT_PRODUCTS_DIR}/Parse.app"
dest="${HOME}/Applications/Parse.app"

if [ ! -d "${product}" ]; then
  echo "error: ${product} was not built" >&2
  exit 1
fi

killall Parse >/dev/null 2>&1 || true
mkdir -p "${HOME}/Applications"
rm -rf "${dest}"
ditto "${product}" "${dest}"

# The shared build is signed so any Mac can run it. On this Mac, sign the
# installed copy with the development certificate when one is present so
# Accessibility permission stays put across rebuilds.
identity=$(security find-identity -p codesigning -v | awk -F'"' '/Apple Development:/{print $2; exit}')
if [ -n "${identity}" ]; then
  codesign --force --sign "${identity}" --options runtime "${dest}"
fi

codesign --verify --strict --verbose=2 "${dest}"
echo "Updated ${dest}"
