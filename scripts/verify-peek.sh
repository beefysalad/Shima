#!/usr/bin/env bash
# Device banner (peek) checks, fake devices only: no Bluetooth, no permission, no screen capture.
#   SHIMA_FAKE_DEVICES=1 SHIMA_FAKE_SPOTIFY=paused scripts/run.sh     (start this checkout first)
#   scripts/verify-peek.sh
# Announce before running: about 70 s of synthetic pointer input near the notch, and one restart of this checkout's
# dist app (by pid) for the Settings-off check; the stored devicePopups default is restored on exit.
# Checks: 1 banner frame 376x84 and no focus change; 2 folds after about 3 s, back to the idle frame; 3 a second device
# replaces the banner and restarts one 3 s timer; 4 hover opens the island once and a stale peek timer cannot collapse
# it; 5 a device while the island is open is dropped; 6 the same device within 5 s is dropped; 7 Settings off (persisted
# devicePopups) drops; 8 the island never became active.
set -uo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
mkdir -p .build
tools="$REPO/.build/tools"; mkdir -p "$tools"
swiftc -O scripts/drive.swift -o "$tools/drive" >/dev/null 2>&1 || { echo "cannot build scripts/drive.swift"; exit 2; }
swiftc -O scripts/shima-windows.swift -o "$tools/shima-windows" >/dev/null 2>&1 || { echo "cannot build scripts/shima-windows.swift"; exit 2; }

mine() { for p in $(pgrep -x Shima || true); do [[ "$(ps -o command= -p "$p" || true)" == "$REPO/dist/Shima.app/"* ]] && echo "$p"; done; return 0; }
pid="$(mine | head -1)"
[[ -n "$pid" ]] || { echo 'Start this checkout first: SHIMA_FAKE_DEVICES=1 SHIMA_FAKE_SPOTIFY=paused scripts/run.sh'; exit 2; }

fail=0
front() { lsappinfo info -only bundleid "$(lsappinfo front)" | sed -E 's/.*="(.*)"/\1/'; }
d() { "$tools/drive" "$1" >/dev/null; }
win() { "$tools/shima-windows" "$@" 2>&1 | tail -1; }
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }

# Only a fake-device instance may be driven: a malformed payload is logged and otherwise ignored.
scripts/with-log.sh .build/peek-probe.log -- "$tools/drive" 'fake-device bogus' >/dev/null
grep -q "Shima\[$pid:.*device fake bad command" .build/peek-probe.log \
  || { echo "Refusing: this checkout is not running with SHIMA_FAKE_DEVICES=1 (no 'device fake bad command' log)"; exit 2; }

read -r music camera header mid hover away rest < <(scripts/island-input-geometry.sh)
orig_defaults="$(defaults read local.shima devicePopups 2>/dev/null || echo __unset__)"
restore_defaults() {
  if [[ "$orig_defaults" == __unset__ ]]; then defaults delete local.shima devicePopups 2>/dev/null
  else defaults write local.shima devicePopups -string "$orig_defaults"; fi
}
trap 'restore_defaults; d "move $mid $away" 2>/dev/null' EXIT

# The system replays connected devices at registration, so the policy drops events in the first 3 s.
uptime_s() { local t; t="$(ps -o etime= -p "$1" | tr -d ' ')"; python3 - "$t" <<'PY'
import sys
t = sys.argv[1]; days = 0
if '-' in t: days, t = t.split('-'); days = int(days)
parts = [int(x) for x in t.split(':')]
while len(parts) < 3: parts.insert(0, 0)
print(days * 86400 + parts[0] * 3600 + parts[1] * 60 + parts[2])
PY
}
wait_grace() { while (( $(uptime_s "$1") < 6 )); do sleep 0.5; done; }

# analyse LOG PID SCRIPT: the python body gets `lines` (this pid's log lines) and helpers.
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

echo "== announcing: about 70 s of synthetic pointer input near the notch =="

# --- checks 1, 2, 8: banner frame, 3 s fold, focus ---
wait_grace "$pid"
front0="$(front)"
cat > .build/peek-a.sh <<EOF
export SHIMA_WINDOW_PID=$pid
"$tools/drive" "move $mid $away; sleep 500" >/dev/null
"$tools/drive" "fake-device connect|Test AirPods|earbuds|82; sleep 800" >/dev/null
echo "FRAME_PEEK \$("$tools/shima-windows" --peek 2>&1 | tail -1)"
echo "FRONT_PEEK \$(lsappinfo info -only bundleid "\$(lsappinfo front)" | sed -E 's/.*="(.*)"/\1/')"
sleep 3.6
echo "FRAME_IDLE \$("$tools/shima-windows" 2>&1 | tail -1)"
EOF
scripts/with-log.sh .build/peek-a.log -- bash .build/peek-a.sh > .build/peek-a.out
grep -q '^FRAME_PEEK PASS peek frame' .build/peek-a.out && ok "1 banner frame is 376x84 centred under the notch" || { bad "1 peek frame: $(grep FRAME_PEEK .build/peek-a.out)"; }
[[ "$(grep ^FRONT_PEEK .build/peek-a.out | cut -d' ' -f2)" == "$front0" ]] && ok "8a the frontmost app did not change during the banner ($front0)" || bad "8a frontmost app changed during the banner"
grep -q '^FRAME_IDLE PASS idle frame' .build/peek-a.out && ok "2 panel is back to the idle frame after the fold" || bad "2 idle frame: $(grep FRAME_IDLE .build/peek-a.out)"
analyse .build/peek-a.log "$pid" '
assert count("device connect kind=earbuds -> shown") == 1, "device connect not shown"
assert count("peek shown earbuds") == 1, "peek shown missing"
assert count("peek dismissed") == 1, "peek not dismissed exactly once"
dt = (when(find("peek dismissed")[0]) - when(find("peek shown earbuds")[0])).total_seconds()
assert 2.5 <= dt <= 4.5, f"fold took {dt:.2f}s, expected about 3 s"
assert count("app became active") == 0, "the island became active"
print(f"PASS 2 folded {dt:.2f}s after it appeared; 8b the island never became active")
' || fail=1

# --- check 3: a second device replaces the banner and restarts one timer ---
scripts/with-log.sh .build/peek-b.log -- "$tools/drive" "move $mid $away; sleep 300; fake-device connect|Test AirPods B|earbuds|82; sleep 1500; fake-device connect|Test Keychron|keyboard|-; sleep 4600" > /dev/null
analyse .build/peek-b.log "$pid" '
assert count("peek shown earbuds") == 1 and count("peek shown keyboard") == 1, "expected one banner per device"
n = count("peek dismissed")
assert n == 1, f"expected a single dismissal, got {n}"
dt = (when(find("peek dismissed")[0]) - when(find("peek shown keyboard")[0])).total_seconds()
assert 2.5 <= dt <= 4.5, f"timer restarted wrongly: fold {dt:.2f}s after the second device"
print(f"PASS 3 second device replaced the banner; one 3 s window after it ({dt:.2f}s), one dismissal")
' || fail=1

# --- checks 4 and 5: hover opens the island once, a stale peek timer cannot collapse it; a device while open is dropped ---
cat > .build/peek-c.sh <<EOF
export SHIMA_WINDOW_PID=$pid
"$tools/drive" "move $mid $away; sleep 300; fake-device connect|Test Mouse|mouse|64; sleep 700; move $mid $hover; sleep 900" >/dev/null
echo "FRAME_OPEN \$("$tools/shima-windows" --expanded 2>&1 | tail -1)"
"$tools/drive" "sleep 3500" >/dev/null
echo "FRAME_STILL_OPEN \$("$tools/shima-windows" --expanded 2>&1 | tail -1)"
"$tools/drive" "fake-device connect|Test Dock|other|-; sleep 900" >/dev/null
echo "FRAME_AFTER_DROP \$("$tools/shima-windows" --expanded 2>&1 | tail -1)"
"$tools/drive" "move $mid $away; sleep 1800" >/dev/null
echo "FRAME_CLOSED \$("$tools/shima-windows" 2>&1 | tail -1)"
EOF
scripts/with-log.sh .build/peek-c.log -- bash .build/peek-c.sh > .build/peek-c.out
grep -q '^FRAME_OPEN PASS expanded' .build/peek-c.out && ok "4a hovering the banner opened the island" || bad "4a island did not open: $(grep FRAME_OPEN .build/peek-c.out)"
grep -q '^FRAME_STILL_OPEN PASS expanded' .build/peek-c.out && ok "4b a stale 3 s peek timer did not collapse the open island" || bad "4b island collapsed after hover: $(grep FRAME_STILL_OPEN .build/peek-c.out)"
grep -q '^FRAME_AFTER_DROP PASS expanded' .build/peek-c.out && ok "5a a device while open left the island alone" || bad "5a frame changed after a device while open"
grep -q '^FRAME_CLOSED PASS idle frame' .build/peek-c.out && ok "4c leaving collapsed the island normally" || bad "4c island did not collapse: $(grep FRAME_CLOSED .build/peek-c.out)"
analyse .build/peek-c.log "$pid" '
n = count("island content=")
assert n == 1, f"island opened {n} times"
assert count("peek shown mouse") == 1, "mouse banner missing"
assert count("peek shown other") == 0, "a banner was shown while the island was open"
assert count("peek dropped") == 1, "the device while open was not reported as dropped"
assert count("kind=other -> drop(islandBusy)") == 1, "service did not log the dropped device"
print("PASS 4 opened exactly once; 5 the device while open was dropped, not shown")
' || fail=1

# --- check 6: the same device within 5 s is dropped ---
scripts/with-log.sh .build/peek-e.log -- "$tools/drive" "move $mid $away; sleep 300; fake-device connect|Test Repeat|keyboard|-; sleep 1000; fake-device connect|Test Repeat|keyboard|-; sleep 4000" > /dev/null
analyse .build/peek-e.log "$pid" '
assert count("kind=keyboard -> shown") == 1, "first connection not shown"
assert count("kind=keyboard -> drop(repeated)") == 1, "the repeat was not dropped"
assert count("peek shown keyboard") == 1, "a second banner was shown"
print("PASS 6 the same device within 5 s was dropped (repeated)")
' || fail=1

# --- check 7: devicePopups off (persisted) drops ---
for p in $(mine); do kill "$p"; done
for _ in $(seq 20); do [[ -z "$(mine)" ]] && break; sleep 0.3; done
defaults write local.shima devicePopups -string off
open --env SHIMA_FAKE_DEVICES=1 --env SHIMA_FAKE_SPOTIFY=paused dist/Shima.app
for _ in $(seq 30); do pid="$(mine | head -1)"; [[ -n "$pid" ]] && break; sleep 0.3; done
[[ -n "$pid" ]] || { echo "FAIL 7 the app did not relaunch"; exit 1; }
wait_grace "$pid"
scripts/with-log.sh .build/peek-f.log -- "$tools/drive" "move $mid $away; sleep 300; fake-device connect|Test Off|keyboard|-; sleep 1200" > /dev/null
analyse .build/peek-f.log "$pid" '
assert count("kind=keyboard -> drop(disabled)") == 1, "the disabled setting did not drop the device"
assert count("peek shown") == 0, "a banner was shown with Device pop-ups off"
print("PASS 7 Device pop-ups off (persisted) dropped the device")
' || fail=1
restore_defaults
for p in $(mine); do kill "$p"; done
for _ in $(seq 20); do [[ -z "$(mine)" ]] && break; sleep 0.3; done
open --env SHIMA_FAKE_DEVICES=1 --env SHIMA_FAKE_SPOTIFY=paused dist/Shima.app
echo "(relaunched this checkout with the original devicePopups setting restored)"

(( fail )) && { echo "FAIL verify-peek"; exit 1; }
echo "PASS verify-peek: frame, fold, replacement, hover, drop while open, repeat, setting off, focus (fake devices)"
