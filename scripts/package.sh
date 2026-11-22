#!/usr/bin/env bash
# Build dist/Shima.app and package it as dist/Shima-<version>.dmg and .zip (not installed, not notarized).
# Signed with SHIMA_SIGN_ID if set, else ad-hoc.
# --release: public release build. Refuses to run if SHIMA_SIGN_ID is set, so a
# release can never embed a personal signing identity; always ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" == "--release" ]]; then
  if [[ -n "${SHIMA_SIGN_ID:-}" ]]; then
    echo "error: --release refuses to run with SHIMA_SIGN_ID set (run: env -u SHIMA_SIGN_ID scripts/package.sh --release)" >&2
    exit 1
  fi
  echo "signed with: - (ad-hoc)"
fi
./scripts/bundle.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Shima.app/Contents/Info.plist)"
ZIP="dist/Shima-$VERSION.zip"
DMG="dist/Shima-$VERSION.dmg"
rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent dist/Shima.app "$ZIP"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto dist/Shima.app "$STAGE/Shima.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Shima" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Wrote $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' '))"
echo "Wrote $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"

(cd dist && shasum -a 256 "Shima-$VERSION.dmg" "Shima-$VERSION.zip" > SHA256SUMS)
echo "Wrote dist/SHA256SUMS"
