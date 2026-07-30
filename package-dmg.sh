#!/usr/bin/env bash
# Builds Toki, runs the security gate, and packages a distributable .dmg.
#
# The security gate is a hard prerequisite: if any guarantee in SECURITY.md is
# broken, no disk image is produced.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Toki"
BUNDLE="build/${APP_NAME}.app"
STAGE="build/dmg-stage"

echo "▸ 빌드"
./build.sh > /dev/null
echo "  ${BUNDLE}"

echo
echo "▸ 보안 게이트"
if ! ./security-check.sh; then
    echo
    echo "❌ 보안 검증 실패 — dmg 를 만들지 않습니다 (SECURITY.md 참조)"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "${BUNDLE}/Contents/Info.plist")
DMG="dist/${APP_NAME}-${VERSION}.dmg"

echo
echo "▸ 디스크 이미지 조립"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE" dist
cp -R "$BUNDLE" "$STAGE/"
# Drag-to-install target inside the mounted image.
ln -s /Applications "$STAGE/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -quiet \
    "$DMG"

rm -rf "$STAGE"

echo "▸ 이미지 검증"
hdiutil verify -quiet "$DMG"

SIZE=$(du -h "$DMG" | cut -f1)
# Checksum file ships next to the image so downloaders can verify it.
( cd dist && shasum -a 256 "${APP_NAME}-${VERSION}.dmg" > "${APP_NAME}-${VERSION}.dmg.sha256" )
SHA=$(cut -d' ' -f1 < "${DMG}.sha256")

# An unversioned copy too: GitHub serves release assets at
# /releases/latest/download/<asset>, so a stable filename gives the README a
# permanent direct-download link that never needs editing on a new version.
STABLE="dist/${APP_NAME}.dmg"
cp "$DMG" "$STABLE"
( cd dist && shasum -a 256 "${APP_NAME}.dmg" > "${APP_NAME}.dmg.sha256" )

echo
echo "✅ ${DMG}  (${SIZE})"
echo "   ${DMG}.sha256"
echo "   SHA-256: ${SHA}"
echo
echo "   열기:   open ${DMG}"
echo "   설치:   마운트된 이미지에서 Toki 를 Applications 로 드래그"
echo
echo "▸ 릴리스로 배포하려면 — 네 파일 모두 첨부해야 README 링크가 동작합니다"
echo "   gh release create v${VERSION} \\"
echo "       ${DMG} ${DMG}.sha256 ${STABLE} ${STABLE}.sha256 \\"
echo "       --title \"Toki ${VERSION}\" --notes-file CHANGELOG.md"
echo "   (gh 가 없으면 GitHub 웹 → Releases → Draft a new release 에서 첨부)"
echo "   ${APP_NAME}.dmg 가 README 의 영구 다운로드 링크 대상입니다"
echo
echo "   ⚠️  ad-hoc 서명이라 Apple 공증이 없습니다. 받는 쪽에서 처음 열 때"
echo "       Gatekeeper 가 막으면 우클릭 → 열기, 또는 아래 한 줄로 해제:"
echo "       xattr -dr com.apple.quarantine /Applications/${APP_NAME}.app"
