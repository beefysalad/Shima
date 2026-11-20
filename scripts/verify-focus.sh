#!/usr/bin/env bash
# Criterion 6: polls the frontmost app every 0.1 s for N seconds (default 15) while you hover the island.
# PASS if the frontmost app never changes and Shima is never frontmost.
set -euo pipefail
secs="${1:-15}"
front() { lsappinfo info -only name "$(lsappinfo front)" | sed 's/.*="\(.*\)"/\1/'; }
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
