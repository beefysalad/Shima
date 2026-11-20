#!/usr/bin/env bash
# Build the app bundle and launch it. Stops any running instance first.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/bundle.sh
pkill -x Shima 2>/dev/null || true
# Forward every SHIMA_* variable (e.g. SHIMA_DEBUG=1) to the launched app.
args=()
while IFS='=' read -r k v; do args+=(--env "$k=$v"); done < <(env | grep '^SHIMA_' || true)
open ${args[@]+"${args[@]}"} dist/Shima.app
