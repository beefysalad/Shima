#!/usr/bin/env bash
# Shelf checks, fake shelf only: no real drag, no pointer input, no permission, no screen capture.
#   SHIMA_FAKE_SHELF=1 SHIMA_FAKE_SPOTIFY=paused scripts/run.sh     (start this checkout first)
#   scripts/verify-shelf.sh
# Announce before running: about 35 s of synthetic fake-shelf commands (distributed notifications). Each segment starts with a
# pointer move to a parked spot away from the notch: an idle (App Nap) app delivers distributed notifications late and in
# bursts, which would make every timing check meaningless (the peek check wakes the app the same way).
# Checks: 1 drag-enter on the collapsed island grows it to the expanded frame (hover phase dragHovering);
# 2 add + drop stores the items, reports "added=3 refused=0", the island stays expanded (dragHovering -> expanded);
# 3 drag-exit collapses back to the idle frame after the leave debounce; 4 a quick exit and re-enter inside the debounce
# never collapses; 5 a 22-file batch fills to the cap (added=20 refused=2 items=20); 6 drop-cancel adds nothing and
# collapses; 7 clear empties the store; 8 the frontmost app never changed and the island never became active.
set -uo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
mkdir -p .build
tools="$REPO/.build/tools"; mkdir -p "$tools"
swiftc -O scripts/drive.swift -o "$tools/drive" >/dev/null 2>&1 || { echo "cannot build scripts/drive.swift"; exit 2; }
swiftc -O scripts/shima-windows.swift -o "$tools/shima-windows" >/dev/null 2>&1 || { echo "cannot build scripts/shima-windows.swift"; exit 2; }

mine() { for p in $(pgrep -x Shima || true); do [[ "$(ps -o command= -p "$p" || true)" == "$REPO/dist/Shima.app/"* ]] && echo "$p"; done; return 0; }
pid="$(mine | head -1)"
[[ -n "$pid" ]] || { echo 'Start this checkout first: SHIMA_FAKE_SHELF=1 SHIMA_FAKE_SPOTIFY=paused scripts/run.sh'; exit 2; }
others="$(for p in $(pgrep -x Shima || true); do [[ "$p" != "$pid" ]] && echo "$p"; done)"
[[ -z "$others" ]] || { echo "Refusing: another Shima is running (pid $others); its island overlaps this one"; exit 2; }

fail=0
front() { lsappinfo info -only bundleid "$(lsappinfo front)" | sed -E 's/.*="(.*)"/\1/'; }
d() { "$tools/drive" "$1" >/dev/null; }
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }

# Only a fake-shelf instance may be driven: every fake command is logged as "shelf fake <command>".
scripts/with-log.sh .build/shelf-probe.log -- "$tools/drive" 'fake-shelf ping' >/dev/null
grep -q "Shima\[$pid:.*shelf fake ping" .build/shelf-probe.log \
  || { echo "Refusing: this checkout is not running with SHIMA_FAKE_SHELF=1 (no 'shelf fake ping' log)"; exit 2; }

analyse() { python3 - "$1" "$2" <<PY
import re, sys
from datetime import datetime
from pathlib import Path
pid = sys.argv[2]
lines = [l for l in Path(sys.argv[1]).read_text().splitlines() if f'Shima[{pid}:' in l]
def when(l): return datetime.strptime(l[:23], '%Y-%m-%d %H:%M:%S.%f')
def find(s): return [l for l in lines if s in l]
def count(s): return len(find(s))
$3
PY
}

# Test files: 22 distinct files for the cap check.
files="$REPO/.build/shelf-files"; rm -rf "$files"; mkdir -p "$files"
batch=""
for i in $(seq -w 1 22); do echo "shelf test file $i" > "$files/f$i.txt"; batch+="fake-shelf add-file $files/f$i.txt; "; done

read -r music camera header mid hover away rest < <(scripts/island-input-geometry.sh)
trap 'd "move $mid $away" 2>/dev/null' EXIT
wake() { d "move $mid $away; sleep 500"; }

echo "== announcing: about 35 s of fake shelf commands, the pointer is parked away from the notch =="
front0="$(front)"
wake
# Start from a known state whatever an earlier run left: enter then exit always ends collapsed.
d "fake-shelf clear; sleep 200; fake-shelf drag-enter; sleep 300; fake-shelf drag-exit; sleep 1500"

wake
cat > .build/shelf-a.sh <<EOF
export SHIMA_WINDOW_PID=$pid
echo "FRAME_COLLAPSED \$("$tools/shima-windows" 2>&1 | tail -1)"
"$tools/drive" "fake-shelf drag-enter; sleep 900" >/dev/null
echo "FRAME_DRAG \$("$tools/shima-windows" --expanded 2>&1 | tail -1)"
"$tools/drive" "fake-shelf add-text hello shelf; fake-shelf add-link https://example.com/page; fake-shelf add-file $files/f01.txt; sleep 200; fake-shelf drop; sleep 1000" >/dev/null
echo "FRAME_DROPPED \$("$tools/shima-windows" --expanded 2>&1 | tail -1)"
"$tools/drive" "sleep 1200" >/dev/null
echo "FRAME_STILL_OPEN \$("$tools/shima-windows" --expanded 2>&1 | tail -1)"
echo "FRONT_A \$(lsappinfo info -only bundleid "\$(lsappinfo front)" | sed -E 's/.*="(.*)"/\1/')"
EOF
scripts/with-log.sh .build/shelf-a.log -- bash .build/shelf-a.sh > .build/shelf-a.out
grep -q '^FRAME_COLLAPSED PASS idle frame' .build/shelf-a.out && ok "0 start state is the idle frame" || bad "0 start frame: $(grep FRAME_COLLAPSED .build/shelf-a.out)"
grep -q '^FRAME_DRAG PASS expanded' .build/shelf-a.out && ok "1 drag-enter grew the collapsed island to the expanded frame" || bad "1 expanded frame: $(grep FRAME_DRAG .build/shelf-a.out)"
grep -q '^FRAME_DROPPED PASS expanded' .build/shelf-a.out && ok "2a the island stays expanded after a drop" || bad "2a after drop: $(grep FRAME_DROPPED .build/shelf-a.out)"
grep -q '^FRAME_STILL_OPEN PASS expanded' .build/shelf-a.out && ok "2b it is still open 1.2 s after the drop (no stray collapse)" || bad "2b collapsed after the drop: $(grep FRAME_STILL_OPEN .build/shelf-a.out)"
analyse .build/shelf-a.log "$pid" '
assert count("hover collapsed -> dragHovering") == 1, "drag-enter did not enter dragHovering from collapsed"
assert count("shelf drop added=3 refused=0 items=3") == 1, "drop of 3 items not reported"
assert count("hover dragHovering -> expanded") == 1, "drop did not return to expanded"
assert count("hover dragHovering -> leaving") == 0, "a drop must not start the leave debounce"
assert count("app became active") == 0, "the island became active"
print("PASS 1/2 collapsed -> dragHovering, drop added=3 refused=0 items=3, dragHovering -> expanded; no activation")
' || fail=1

# --- check 3: drag-exit collapses after the debounce (the island is open from the drop above) ---
wake
cat > .build/shelf-b.sh <<EOF
export SHIMA_WINDOW_PID=$pid
"$tools/drive" "fake-shelf drag-enter; sleep 600; fake-shelf drag-exit; sleep 1800" >/dev/null
echo "FRAME_EXIT \$("$tools/shima-windows" 2>&1 | tail -1)"
EOF
scripts/with-log.sh .build/shelf-b.log -- bash .build/shelf-b.sh > .build/shelf-b.out
grep -q '^FRAME_EXIT PASS idle frame' .build/shelf-b.out && ok "3 drag-exit collapsed the island to the idle frame" || bad "3 idle frame after exit: $(grep FRAME_EXIT .build/shelf-b.out)"
analyse .build/shelf-b.log "$pid" '
assert count("hover dragHovering -> leaving") == 1, "exit did not start the leave debounce"
assert count("hover leaving -> collapsing") == 1, "debounce did not collapse"
dt = (when(find("hover leaving -> collapsing")[0]) - when(find("hover dragHovering -> leaving")[0])).total_seconds()
assert 0.2 <= dt <= 0.6, f"leave debounce took {dt:.2f}s, expected about 0.3 s"
print(f"PASS 3 dragHovering -> leaving -> collapsing after {dt:.2f}s")
' || fail=1

# --- check 4: exit then re-enter inside the debounce never collapses ---
wake
cat > .build/shelf-c.sh <<EOF
export SHIMA_WINDOW_PID=$pid
"$tools/drive" "fake-shelf drag-enter; sleep 700; fake-shelf drag-exit; sleep 140; fake-shelf drag-enter; sleep 1500" >/dev/null
echo "FRAME_REENTER \$("$tools/shima-windows" --expanded 2>&1 | tail -1)"
"$tools/drive" "fake-shelf drop-cancel; sleep 1800" >/dev/null
echo "FRAME_CANCEL \$("$tools/shima-windows" 2>&1 | tail -1)"
EOF
scripts/with-log.sh .build/shelf-c.log -- bash .build/shelf-c.sh > .build/shelf-c.out
grep -q '^FRAME_REENTER PASS expanded' .build/shelf-c.out && ok "4 exit then re-enter 140 ms later stayed expanded" || bad "4 re-enter: $(grep FRAME_REENTER .build/shelf-c.out)"
grep -q '^FRAME_CANCEL PASS idle frame' .build/shelf-c.out && ok "6a drop-cancel collapsed the island" || bad "6a after cancel: $(grep FRAME_CANCEL .build/shelf-c.out)"
analyse .build/shelf-c.log "$pid" '
assert count("hover leaving -> dragHovering") == 1, "re-enter did not cancel the leave debounce"
assert count("hover dragHovering -> collapsing") == 0 and count("hover leaving -> collapsing") == 1, "expected one collapse, after the cancel"
assert count("shelf drag ended(dropped: false)") == 1, "drop-cancel did not report ended(dropped: false)"
assert count("shelf drop added=") == 0, "a cancel must not add anything"
print("PASS 4 re-enter inside the debounce stayed open; 6 drop-cancel ended(dropped: false) and added nothing")
' || fail=1

# --- check 5 and 7: the cap, then clear ---
wake
scripts/with-log.sh .build/shelf-d.log -- "$tools/drive" "fake-shelf clear; sleep 200; fake-shelf drag-enter; sleep 600; ${batch}sleep 300; fake-shelf drop; sleep 800; fake-shelf clear; sleep 300; fake-shelf drag-enter; sleep 300; fake-shelf drag-exit; sleep 1500" > /dev/null
SHIMA_WINDOW_PID=$pid "$tools/shima-windows" 2>&1 | tail -1 | grep -q "^PASS idle frame" && ok "5b the island is back to the idle frame at the end" || bad "5b island not idle at the end: $(SHIMA_WINDOW_PID=$pid "$tools/shima-windows" 2>&1 | tail -1)"
analyse .build/shelf-d.log "$pid" '
assert count("shelf drop added=20 refused=2 items=20") == 1, "22 files onto an empty shelf did not give added=20 refused=2 items=20"
assert count("shelf cleared items=0") >= 2, "clear did not empty the store"
print("PASS 5 a 22-file batch filled the shelf to the cap (added=20 refused=2 items=20); 7 clear emptied it")
' || fail=1

# --- check 8: focus ---
[[ "$(front)" == "$front0" ]] && ok "8 the frontmost app never changed ($front0)" || bad "8 frontmost app changed: was $front0, now $(front)"
cat .build/shelf-*.log | grep -q "Shima\[$pid:.*app became active" && bad "8 the island became active" || ok "8 the island never became active"

(( fail )) && { echo "FAIL verify-shelf"; exit 1; }
echo "PASS verify-shelf: drag-enter, drop, exit debounce, re-enter, cancel, cap, clear, focus (fake shelf)"
