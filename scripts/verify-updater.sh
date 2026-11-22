#!/usr/bin/env bash
# Offscreen GUI and archive checks using a fixture release; never replaces the installed app.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
bin="$(swift build --show-bin-path)"
out="$PWD/.build/updater-regression"
mkdir -p "$out"
objects=()
if [[ -f "$bin/ShimaCore.o" ]]; then
    objects+=("$bin/ShimaCore.o")
else
    shopt -s nullglob
    objects+=("$bin"/ShimaCore.build/*.o)
fi
swiftc -swift-version 6 -parse-as-library -I "$bin" \
    Sources/Shima/AppUpdater.swift Sources/Shima/SigningInfo.swift Sources/Shima/SettingsView.swift \
    scripts/updater-check.swift "${objects[@]}" -o "$out/check"
swiftc -swift-version 6 -D UPDATER_TESTING -parse-as-library -I "$bin" \
    Sources/ShimaUpdater/main.swift "${objects[@]}" -o "$out/helper-test"
"$out/check" "$@"
