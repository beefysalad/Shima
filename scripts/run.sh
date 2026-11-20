#!/usr/bin/env bash
# Build the app bundle and launch it. Stops any running instance first.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/bundle.sh
pkill -x Shima 2>/dev/null || true
open dist/Shima.app
