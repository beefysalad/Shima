#!/usr/bin/env bash
# Criterion 6: polls the frontmost app every 0.1 s for N seconds (default 15) while you hover the island.
# PASS if the frontmost app never changes and Shima is never frontmost.
set -euo pipefail
front() { lsappinfo info -only name "$(lsappinfo front)" | sed 's/.*="\(.*\)"/\1/'; }
if [[ "${1:-}" == "--clicks" ]]; then
  # Hands-off, fake mode only: real clicks on the island buttons must not change the frontmost app.
  cd "$(dirname "$0")/.."
  mkdir -p .build
  dir="$(mktemp -d .build/shima-focus.XXXXXX)"
  pid=""
  for candidate in $(pgrep -x Shima || true); do
    [[ "$(ps -o command= -p "$candidate" || true)" != "$PWD/dist/Shima.app/Contents/MacOS/Shima" ]] || pid="$candidate"
  done
  [[ -n "$pid" ]] || { echo "Start this checkout with SHIMA_FAKE_SPOTIFY=paused scripts/run.sh"; exit 2; }
  scripts/with-log.sh "$dir/ping.log" -- swift scripts/drive.swift "fake ping" >/dev/null
  grep -q "Shima\[$pid:.*\[local.shima:spotify\] fake ping" "$dir/ping.log" || { echo "not in fake mode (SHIMA_FAKE_SPOTIFY=playing scripts/run.sh)"; exit 2; }
  read -r music camera header mid hover away mirrorX mirrorY previousX previousY playX playY nextX nextY blankX blankY calendar < <(scripts/island-input-geometry.sh)
  before="$(front)"
  scripts/with-log.sh "$dir/clicks.log" -- swift scripts/drive.swift "fake ping; fake playing; move $mid $away; sleep 500; move $mid $hover; sleep 700; click-owned $pid $music $header; sleep 200; click-owned $pid $previousX $previousY; sleep 400; click-owned $pid $playX $playY; sleep 400; click-owned $pid $nextX $nextY; sleep 400; click-owned $pid $blankX $blankY; sleep 300; move $mid $away; sleep 1500" > "$dir/drive.log" || { cat "$dir/drive.log" >&2; exit 2; }
  after="$(front)"
  target_log="$dir/checkout.log"
  grep -F "Shima[$pid:" "$dir/clicks.log" > "$target_log" || true
  n="$(grep -c 'spotify command [A-Za-z]* active=false key=false' "$target_log" || true)"
  fail=""
  [[ "$n" == 3 ]] || fail="expected 3 commands with active=false key=false, got $n ($target_log)"
  if grep -qE 'spotify command .*(active=true|key=true)' "$target_log"; then fail="a command ran with active=true or key=true"; fi
  if grep -q 'app became active' "$target_log"; then fail="app became active"; fi
  [[ "$before" == "$after" ]] || fail="frontmost changed: $before -> $after"
  [[ "$after" != "Shima" ]] || fail="Shima is frontmost"
  kill -0 "$pid" 2>/dev/null || fail="Checkout Shima is not running"
  if [[ -n "$fail" ]]; then echo "FAIL $fail"; exit 1; fi
  echo "PASS clicks: 3 commands, frontmost unchanged: $after"
  exit 0
fi
secs="${1:-15}"
echo "click into the app that should keep focus (3 s)..."; sleep 3
start="$(front)"; changed=0
echo "frontmost at start: $start (hover the island now, for ${secs}s)"
end=$((SECONDS + secs))
while (( SECONDS < end )); do
  now="$(front)"
  if [[ "$now" != "$start" ]]; then echo "CHANGED -> $now"; changed=1; start="$now"; fi
  sleep 0.1
done
if (( changed == 0 )) && [[ "$start" != "Shima" ]]; then echo "PASS frontmost unchanged: $start"; else echo "FAIL"; exit 1; fi
