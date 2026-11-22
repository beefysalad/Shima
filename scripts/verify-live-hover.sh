#!/usr/bin/env bash
# Criterion 6 in the live state, fake mode only (SHIMA_FAKE_SPOTIFY=paused scripts/run.sh). Hands off the mouse.
set -uo pipefail
cd "$(dirname "$0")/.."
N="735 16"; A="735 400"; W="630 16"
dir="$(mktemp -d -t shima-live)"; fail=0
d() { swift scripts/drive.swift "$1" >/dev/null; }
seq_run() { # name, prep, steps
  d "$2; move $A; sleep 1500"
  scripts/with-log.sh "$dir/$1.log" -- swift scripts/drive.swift "$3" >/dev/null
  grep -E 'frame (idle|expanded)|hover |fake ' "$dir/$1.log" > "$dir/$1.ev" || true
}
count() { grep -c -- "$2" "$dir/$1.ev" || true; }
check() { if [[ "$3" == "$4" ]]; then echo "ok   $1: $2"; else echo "FAIL $1: $2 (got $3, want $4; $dir/$1.ev)"; fail=1; fi; }
last_frame() { grep 'frame ' "$dir/$1.ev" | tail -1 | grep -oE 'w=[0-9.]+' || echo none; }

scripts/with-log.sh "$dir/ping.log" -- swift scripts/drive.swift "fake ping" >/dev/null
grep -q 'fake ping' "$dir/ping.log" || { echo "not in fake mode (SHIMA_FAKE_SPOTIFY=paused scripts/run.sh)"; exit 2; }

seq_run A "fake paused" "$(printf 'fake playing; sleep 400; fake paused; sleep 400; %.0s' 1 2 3 4 5)"
check A "idle frames" "$(count A 'frame idle')" 10;  check A "no hover" "$(count A 'hover ')" 0
seq_run B "fake paused" "move $N; sleep 700; fake playing; sleep 400; move $A; sleep 1500"
check B "one grow" "$(count B 'frame expanded')" 1;  check B "one idle frame" "$(count B 'frame idle')" 1
check B "ends live" "$(last_frame B)" "w=245.0"
seq_run C "fake playing" "move $N; sleep 700; fake paused; sleep 400; move $A; sleep 1500"
check C "one grow" "$(count C 'frame expanded')" 1;  check C "ends not live" "$(last_frame C)" "w=179.0"
seq_run D "fake paused" "move $N; sleep 30; fake playing; sleep 700; move $A; sleep 1500"
check D "one grow" "$(count D 'frame expanded')" 1;  check D "ends live" "$(last_frame D)" "w=245.0"
check D "one collapse" "$(count D '-> collapsing')" 1
seq_run E "fake paused" "move $N; sleep 150; fake playing; sleep 600; move $A; sleep 1500"
check E "one grow" "$(count E 'frame expanded')" 1;  check E "one idle frame" "$(count E 'frame idle')" 1
seq_run F "fake playing" "move $N; sleep 700; move $A; sleep 400; move $N; sleep 20; fake paused; sleep 700; move $A; sleep 1500"
check F "re-entry" "$(count F 'collapsing -> dwelling')" 1;  check F "one grow" "$(count F 'frame expanded')" 1
check F "one idle frame" "$(count F 'frame idle')" 1;  check F "ends not live" "$(last_frame F)" "w=179.0"
seq_run G "fake playing" "move $W; sleep 30; fake paused; sleep 500"
check G "shrinks" "$(count G 'frame idle')" 1;  check G "dwell cancelled" "$(count G 'dwelling -> collapsed')" 1
check G "no grow" "$(count G 'frame expanded')" 0
seq_run H "fake playing" "move $N; sleep 700; $(printf 'move 735 213; sleep 50; move 735 200; sleep 50; %.0s' $(seq 20)) move $A; sleep 1500"
check H "one collapse" "$(count H '-> collapsing')" 1;  check H "one grow" "$(count H 'frame expanded')" 1
# Timing from B's log (compact style: field 2 is hh:mm:ss.mmm).
ms() { grep -m1 -- "$2" "$dir/$1.log" | awk '{ split($2, t, ":"); printf "%d", (t[1]*3600 + t[2]*60 + t[3]) * 1000 }'; }
dwell=$(( $(ms B 'dwelling -> expanded') - $(ms B 'collapsed -> dwelling') ))
debounce=$(( $(ms B 'leaving -> collapsing') - $(ms B 'expanded -> leaving') ))
echo "dwell ${dwell} ms (want 60-150), debounce ${debounce} ms (want 280-420)"
(( dwell >= 60 && dwell <= 150 && debounce >= 280 && debounce <= 420 )) || { echo "FAIL timing"; fail=1; }
d "move $A; fake paused"   # leave the island not live so verify-idle.sh does not refuse
(( fail == 0 )) && echo "PASS live hover" || { echo "FAIL live hover"; exit 1; }
