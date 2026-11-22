#!/usr/bin/env bash
# Build dist/Shima.app and install it to /Applications/Shima.app (like a locally built app, no notarization).
# Usage: [SHIMA_SIGN_ID="Apple Development: ..."] scripts/install.sh [--open]
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
DEST="/Applications/Shima.app"
OPEN=0
for a in "$@"; do
  case "$a" in
    --open) OPEN=1 ;;
    *) echo "unknown argument: $a (usage: scripts/install.sh [--open])" >&2; exit 2 ;;
  esac
done

if [[ -d "$DEST" ]]; then
  id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$id" != "local.shima" ]]; then
    echo "Refusing: $DEST exists but its CFBundleIdentifier is '${id:-unreadable}', not local.shima." >&2
    exit 1
  fi
  if [[ -z "${SHIMA_SIGN_ID:-}" ]] && codesign -dvv "$DEST" 2>&1 | grep -q '^Authority=Apple Development'; then
    echo "Refusing: $DEST is signed with an Apple Development identity, and an ad-hoc build would lose the Automation (Spotify) grant." >&2
    echo "Set SHIMA_SIGN_ID to the same identity, for example: SHIMA_SIGN_ID='Apple Development: you@example.com (TEAMID)' scripts/install.sh" >&2
    exit 1
  fi
fi

./scripts/bundle.sh

# Quit a running Shima by pid, but only if it runs from /Applications or this repo's dist.
for pid in $(pgrep -x Shima || true); do
  cmd="$(ps -o command= -p "$pid" || true)"
  case "$cmd" in
    "$DEST/"*|"$REPO/dist/Shima.app/"*) echo "Quitting running Shima (pid $pid)"; kill "$pid" ;;
    *) echo "Leaving Shima pid $pid alone (runs from elsewhere: $cmd)" ;;
  esac
done
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Shima >/dev/null || break; sleep 0.3; done

rm -rf "$DEST"
ditto dist/Shima.app "$DEST"
codesign --verify --deep --strict "$DEST"
echo "Installed $DEST"
codesign -dr - "$DEST" 2>&1 | grep -i 'designated' || true
(( OPEN )) && open "$DEST"
exit 0
