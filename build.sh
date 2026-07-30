#!/usr/bin/env bash
# Builds Toki.app from the SwiftPM executable and ad-hoc signs it.
#
# No Xcode project and no developer account required: the app bundle is assembled
# by hand and signed ad-hoc with the hardened runtime, which is enough to run it
# locally. No entitlements are requested — Toki needs no network, no camera, and
# no privileged access.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Toki"
CONFIGURATION="release"
BUNDLE="build/${APP_NAME}.app"

swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

codesign --force --options runtime --sign - "$BUNDLE"
codesign --verify --strict "$BUNDLE"

echo
echo "✅ ${BUNDLE}"
echo "   실행:   open ${BUNDLE}"
echo "   설치:   cp -R ${BUNDLE} /Applications/"
echo "   검증:   ./security-check.sh"
