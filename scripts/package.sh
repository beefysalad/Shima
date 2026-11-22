#!/usr/bin/env bash
# Build dist/Shima.app and zip it to dist/Shima-<version>.zip (not installed, not notarized).
# Signed with SHIMA_SIGN_ID if set, else ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/bundle.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Shima.app/Contents/Info.plist)"
ZIP="dist/Shima-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent dist/Shima.app "$ZIP"
echo "Wrote $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' '))"
