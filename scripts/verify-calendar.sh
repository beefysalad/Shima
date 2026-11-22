#!/usr/bin/env bash
# CGEvent check for the fake Calendar tab. Start a fresh checkout with
# SHIMA_FAKE_CALENDAR=1 SHIMA_FAKE_SPOTIFY=paused scripts/run.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
pid=""
for candidate in $(pgrep -x Shima || true); do
  [[ "$(ps -o command= -p "$candidate" || true)" != "$PWD/dist/Shima.app/Contents/MacOS/Shima" ]] || pid="$candidate"
done
[[ -n "$pid" ]] || { echo 'Start this checkout with SHIMA_FAKE_CALENDAR=1 SHIMA_FAKE_SPOTIFY=paused scripts/run.sh'; exit 2; }
scripts/with-log.sh .build/calendar-probe.log -- swift scripts/drive.swift 'fake-calendar ping' >/dev/null
python3 - "$pid" <<'PY'
import sys
from pathlib import Path

lines = Path('.build/calendar-probe.log').read_text().splitlines()
if not any(f'Shima[{sys.argv[1]}:' in line and '[local.shima:calendar] calendar fake ping' in line for line in lines):
    sys.exit('Refusing clicks: this checkout did not answer the fake Calendar probe')
PY

geometry="$(scripts/island-input-geometry.sh)"
read -r music camera header mid hover away mirror_x mirror_y previous_x previous_y play_x play_y next_x next_y artwork_x artwork_y calendar_x <<< "$geometry"
controls="$(.build/island-input-geometry --calendar-controls)"
read -r previous_month next_month month_y <<< "$controls"
[[ -n "$calendar_x" && -n "$month_y" ]] || { echo 'Calendar geometry unavailable' >&2; exit 2; }

# Command markers let the assertions attribute effects to one action at a time.
scripts/with-log.sh .build/calendar-verification.log -- swift scripts/drive.swift \
  "move $music $away; sleep 1500; move $mid $away; sleep 1500" \
  "fake-calendar begin-hover; sleep 100; move $mid $hover; sleep 700" \
  "fake-calendar begin-calendar; sleep 100; click-owned $pid $calendar_x $header; sleep 400" \
  "fake-calendar begin-previous; sleep 100; click-owned $pid $previous_month $month_y; sleep 400" \
  "fake-calendar begin-next; sleep 100; click-owned $pid $next_month $month_y; sleep 400" \
  "fake-calendar denied; sleep 400; fake-calendar allowed; sleep 400" \
  "fake-calendar changed; sleep 400; fake-calendar daychanged; sleep 400" \
  "fake-calendar begin-collapse; sleep 100; move $mid $away; sleep 1500" \
  "fake-calendar changed; sleep 400" \
  "fake-calendar begin-rehover; sleep 100; move $mid $hover; sleep 700" \
  "fake-calendar begin-reopen; sleep 100; click-owned $pid $calendar_x $header; sleep 400" \
  "fake-calendar begin-finish; sleep 100; move $mid $away; sleep 1500"

python3 - "$pid" <<'PY'
import re
import sys
from pathlib import Path

log = Path('.build/calendar-verification.log')
text = '\n'.join(line for line in log.read_text().splitlines() if f'Shima[{sys.argv[1]}:' in line)
markers = re.split(r'\[local\.shima:calendar\] calendar fake (\S+)\n', text)
expected = ['begin-hover', 'begin-calendar', 'begin-previous', 'begin-next', 'denied', 'allowed',
            'changed', 'daychanged', 'begin-collapse', 'changed', 'begin-rehover', 'begin-reopen', 'begin-finish']
assert markers[1::2] == expected, f'unexpected phase markers: {markers[1::2]} ({log})'
phases = markers[2::2]
assert not re.search(r'\[local\.shima:calendar\] calendar (request|load) ', markers[0]), f'calendar call before the first hover ({log})'
for index, (phase, body, loads) in enumerate(zip(expected, phases, [0, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 1, 0])):
    effects = re.findall(r'\[local\.shima:calendar\] calendar (load|request) (.*)', body)
    actual_loads = [effect for kind, effect in effects if kind == 'load']
    requests = [effect for kind, effect in effects if kind == 'request']
    assert len(actual_loads) == loads, f'{phase}: expected {loads} loads, got {actual_loads} ({log})'
    assert requests == (['events', 'reminders'] if index == 1 else []), f'{phase}: unexpected requests: {requests} ({log})'

def loaded_range(body):
    return re.search(r'\[local\.shima:calendar\] calendar load (.*)', body)[1]

initial, previous, returned = map(loaded_range, phases[1:4])
assert previous != initial and returned == initial, f'month arrows did not browse out and back ({log})'
assert 'calendar access events=denied reminders=denied' in phases[4], f'denied state not logged ({log})'
assert 'calendar access events=authorized reminders=authorized' in phases[5], f'allowed state not logged ({log})'
for index in (0, 10):
    assert 'frame expanded ' in phases[index], f'{expected[index]}: the island did not expand ({log})'
assert 'frame idle ' in phases[8], f'the island did not collapse before the hidden change ({log})'
assert 'app became active' not in text, f'island stole focus ({log})'
print('PASS calendar: Music gating, permission order and denial, month arrows, store/day changes, and collapse/reopen (fake)')
PY
