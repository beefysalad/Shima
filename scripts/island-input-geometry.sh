#!/usr/bin/env bash
# Compile the shared screen/layout-to-CGEvent coordinate helper after swift build.
set -euo pipefail
cd "$(dirname "$0")/.."
bin="$(swift build --show-bin-path)"
objects=("$bin"/ShimaCore.build/*.o)
[[ ! -f "$bin/ShimaCore.o" ]] || objects=("$bin/ShimaCore.o")
swiftc -swift-version 6 -parse-as-library -I "$bin" Sources/Shima/ScreenLocator.swift scripts/island-input-geometry.swift "${objects[@]}" -o .build/island-input-geometry
.build/island-input-geometry
