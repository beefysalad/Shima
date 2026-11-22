#!/usr/bin/env bash
# Build the app bundle and launch it. Stops this checkout's running dist instance first (by pid).
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${SHIMA_FAKE_SPOTIFY:-}" && -z "${SHIMA_SIGN_ID:-}" ]]; then
  echo "Real mode needs SHIMA_SIGN_ID (a stable signature keeps the Automation grant); for fake mode set SHIMA_FAKE_SPOTIFY. Refusing to build." >&2
  exit 1
fi
./scripts/bundle.sh
REPO="$PWD"
# Stop only this checkout's dist build, by pid. Codex's worktree build and the installed app keep running.
mine() { for p in $(pgrep -x Shima || true); do [[ "$(ps -o command= -p "$p" || true)" == "$REPO/dist/Shima.app/"* ]] && echo "$p"; done; return 0; }
for pid in $(mine); do kill "$pid"; done
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -z "$(mine)" ]] && break; sleep 0.3; done
for pid in $(pgrep -x Shima || true); do
  echo "Leaving Shima pid $pid alone (runs from elsewhere: $(ps -o command= -p "$pid" || true))"
  echo "warning: another Shima is running; its island overlaps this one"
done
# Forward every SHIMA_* variable (e.g. SHIMA_DEBUG=1) to the launched app.
args=()
while IFS='=' read -r k v; do args+=(--env "$k=$v"); done < <(env | grep '^SHIMA_' || true)
open ${args[@]+"${args[@]}"} dist/Shima.app
