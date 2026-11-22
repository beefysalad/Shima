#!/usr/bin/env bash
# Render actual views into an in-memory cacheDisplay bitmap. No window is shown.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
bin="$(swift build --show-bin-path)"
out="$PWD/.build/view-layout-regression"
mkdir -p "$out"
cp Sources/Shima/Resources/*.png "$out/"
objects=()
if [[ -f "$bin/ShimaCore.o" ]]; then
    objects+=("$bin/ShimaCore.o")
else
    shopt -s nullglob
    objects+=("$bin"/ShimaCore.build/*.o)
    [[ ${#objects[@]} -gt 0 ]] || { echo "Cannot find built ShimaCore objects" >&2; exit 1; }
fi
sources=(Sources/Shima/ArtworkCache.swift Sources/Shima/IslandMedia.swift Sources/Shima/Log.swift
    Sources/Shima/CameraCaptureClient.swift Sources/Shima/CameraService.swift Sources/Shima/CameraContent.swift
    Sources/Shima/EqualizerView.swift Sources/Shima/WingsView.swift Sources/Shima/IslandView.swift Sources/Shima/BrandAssets.swift
    Sources/Shima/PeekContent.swift)
[[ ! -f Sources/Shima/NowPlayingView.swift ]] || sources+=(Sources/Shima/NowPlayingView.swift)
swiftc -swift-version 6 -parse-as-library -I "$bin" "${sources[@]}" \
    scripts/view-layout-check.swift "${objects[@]}" -o "$out/check"
"$out/check" "$@"
