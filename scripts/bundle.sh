#!/usr/bin/env bash
# Build release binaries and assemble an ad-hoc-signed dist/Shima.app. No Xcode needed.
set -euo pipefail
cd "$(dirname "$0")/.."
SIGN_ID="${SHIMA_SIGN_ID:--}"

swift build -c release
BIN="$(swift build -c release --show-bin-path)"

APP="dist/Shima.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Shima" "$APP/Contents/MacOS/Shima"
cp "$BIN/shimactl" "$APP/Contents/MacOS/shimactl"
cp assets/branding/shima.icns "$APP/Contents/Resources/shima.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Shima</string>
    <key>CFBundleDisplayName</key><string>Shima</string>
    <key>CFBundleIdentifier</key><string>local.shima</string>
    <key>CFBundleExecutable</key><string>Shima</string>
    <key>CFBundleIconFile</key><string>shima.icns</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1.1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>shima shows what Spotify is playing and sends it play, pause, next and previous when you click the island's buttons.</string>
</dict>
</plist>
PLIST

codesign --force --timestamp=none -s "$SIGN_ID" "$APP/Contents/MacOS/shimactl"
codesign --force --timestamp=none -s "$SIGN_ID" "$APP"
echo "signed with: $SIGN_ID"
echo "Built $APP"
