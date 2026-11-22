#!/usr/bin/env bash
# CGEvent header/lifecycle check. Requires SHIMA_FAKE_CAMERA=1 scripts/run.sh.
# No camera hardware, permissions, screen capture, real lock or sleep.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
pid=""
for p in $(pgrep -x Shima || true); do
  [[ "$(ps -o command= -p "$p" || true)" != "$PWD/dist/Shima.app/"* ]] || pid="$p"
done
[[ -n "$pid" ]] || { echo 'Start this checkout with SHIMA_FAKE_CAMERA=1 scripts/run.sh'; exit 2; }
scripts/with-log.sh .build/camera-probe.log -- swift scripts/drive.swift 'camera ping' >/dev/null
python3 - "$pid" <<'PYPROBE'
import sys
from pathlib import Path
lines = Path('.build/camera-probe.log').read_text().splitlines()
if not any(f'Shima[{sys.argv[1]}:' in line and 'camera fake ping' in line for line in lines):
    print('Refusing clicks: this checkout is not running with SHIMA_FAKE_CAMERA=1', file=sys.stderr)
    sys.exit(2)
PYPROBE
read -r music camera header mid hover away mirrorX mirrorY rest < <(scripts/island-input-geometry.sh)
scripts/with-log.sh .build/camera-verification.log -- swift scripts/drive.swift "move $mid $away; sleep 1500; fake paused; move $mid $hover; sleep 700; click $music $header; sleep 200; move $mid $away; sleep 1500; camera begin-hover; move $mid $hover; sleep 700; camera end-hover; click $camera $header; sleep 300; click $music $header; sleep 300; click $camera $header; sleep 300; camera lock; sleep 200; camera unlock; sleep 200; camera session-resign; sleep 200; camera session-active; sleep 200; camera sleep; camera system-sleep; camera wake; sleep 200; camera system-wake; sleep 200; camera denied; sleep 300; camera permission-external-allowed; camera return-from-settings; sleep 200; click $mirrorX $mirrorY; sleep 200; move $mid $away; sleep 1500; camera begin-rehover; move $mid $hover; sleep 700; camera end-rehover; click $camera $header; sleep 300; click $music $header; sleep 200; camera permission-pending; click $camera $header; sleep 300; camera deny; sleep 300; camera allowed; sleep 200; move $mid $away; sleep 1500"
python3 - "$pid" <<'PY'
import re, sys
from pathlib import Path
text = '\n'.join(line for line in Path('.build/camera-verification.log').read_text().splitlines()
                 if f'Shima[{sys.argv[1]}:' in line)
assert 'camera tab clicked tab=camera active=false' in text, 'Camera header click swallowed or app active'
assert 'camera tab clicked tab=music active=false' in text, 'Music header click swallowed or app active'
assert 'active=true' not in text, 'a control activated the app'
hover = text.split('camera fake begin-hover', 1)[1].split('camera fake end-hover', 1)[0]
assert 'session start' not in hover, 'initial hover started camera'
rehover = text.split('camera fake begin-rehover', 1)[1].split('camera fake end-rehover', 1)[0]
assert 'session start' not in rehover, 'hover after leaving Camera selected restarted camera'
returned = text.split('camera fake return-from-settings', 1)[1].split('camera mirror=', 1)[0]
assert 'session start' in returned, 'return from Settings did not refresh permission'
resigned = text.split('camera fake session-resign', 1)[1].split('camera fake session-active', 1)[0]
assert 'session stop' in resigned and 'session start' not in resigned, 'inactive user session kept camera running'
assert 'camera mirror=false' in text, 'mirror toggle click missing'
assert 'camera fake permission requested' in text, 'fake permission request missing'
# Current-intent sequence includes stop on tab switch, lock, display sleep,
# revocation, collapse, and denial, plus restarts on eligible returns.
events = re.findall(r'camera fake session (start|stop)', text)
assert events == ['start', 'stop'] * 8, f'unexpected lifecycle sequence: {events}'
sleep = text.split('camera fake wake', 1)[1].split('camera fake system-wake', 1)[0]
assert 'session start' not in sleep, 'display wake restarted while system asleep'
denial = text.split('camera fake deny\n', 1)[1].split('camera fake allowed', 1)[0]
assert 'session start' not in denial, 'denied camera started'
assert 'app became active' not in text, 'island stole focus'
print('PASS camera: header clicks, hover, mirror, permission/denial, tab, collapse, lock/sleep and restart (fake)')
PY
if [[ "${1:-}" == --quit ]]; then
  scripts/with-log.sh .build/camera-quit-verification.log -- swift scripts/drive.swift "move $mid $hover; sleep 700; click $camera $header; sleep 200; camera quit $pid; sleep 400"
  python3 - "$pid" <<'PYQUIT'
import subprocess, sys
from pathlib import Path
text = '\n'.join(line for line in Path('.build/camera-quit-verification.log').read_text().splitlines()
                 if f'Shima[{sys.argv[1]}:' in line)
assert 'camera fake session start' in text, 'quit check never opened fake camera'
assert 'camera fake session stop' in text.split('camera fake quit', 1)[1], 'quit did not stop capture'
command = subprocess.run(['ps', '-o', 'command=', '-p', sys.argv[1]], capture_output=True, text=True).stdout.strip()
assert not command, f'app did not exit after asynchronous camera cleanup: {command}'
print('PASS camera quit: capture stopped and checkout process exited')
PYQUIT
fi
