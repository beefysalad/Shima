#!/usr/bin/env bash
# Build the app bundle and launch it. Stops any running instance first.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${SHIMA_FAKE_SPOTIFY:-}" && -z "${SHIMA_SIGN_ID:-}" ]] && pgrep -x Spotify >/dev/null; then
  echo "Spotify is running: a real-mode build needs SHIMA_SIGN_ID (stable Automation grant) or SHIMA_FAKE_SPOTIFY." >&2
  exit 1
fi
./scripts/bundle.sh
pkill -x Shima 2>/dev/null || true
# Forward every SHIMA_* variable (e.g. SHIMA_DEBUG=1) to the launched app.
args=()
while IFS='=' read -r k v; do args+=(--env "$k=$v"); done < <(env | grep '^SHIMA_' || true)
open ${args[@]+"${args[@]}"} dist/Shima.app
