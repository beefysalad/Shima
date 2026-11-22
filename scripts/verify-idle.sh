#!/usr/bin/env bash
# Criterion 7/10: keep the pointer away from the notch for the whole run.
#   scripts/verify-idle.sh            strict idle: Spotify not playing (island not live), 60 s, ~0 CPU
#   scripts/verify-idle.sh --growth   memory growth: 20 open/close cycles (Music and Calendar tabs, device banners when fake modes
#                                     are on); RSS must flatten out (grows < 6 MB from cycle 5 to cycle 20) and stay < 80 MB.
#                                     Moves the pointer for about 60 s; needs the fake services, never real Calendar/Bluetooth.
#   scripts/verify-idle.sh --playing  island live (SHIMA_FAKE_SPOTIFY=playing): Shima CPU plus an equalizer
#                                     animating/frozen A/B on Shima and WindowServer (needs the screen awake and unlocked)
set -euo pipefail
cd "$(dirname "$0")/.."
mode=idle; [[ "${1:-}" == "--playing" ]] && mode=playing; [[ "${1:-}" == "--growth" ]] && mode=growth
fail=0
echo "static check: no timers, event monitors or display links; repeating animations only where allowed"
hits="$(grep -rnE 'addGlobalMonitorForEvents|addLocalMonitorForEvents|scheduledTimer|(^|[^A-Za-z])Timer[(.]|CVDisplayLink|CADisplayLink|displayLink|repeatForever|repeatCount|TimelineView' Sources/Shima Sources/ShimaCore \
  | grep -vE '^Sources/Shima/EqualizerView\.swift:[0-9]+:.*repeatCount' \
  | grep -vE '^Sources/Shima/NowPlayingView\.swift:[0-9]+:.*TimelineView' || true)"
if [[ -n "$hits" ]]; then echo "$hits"; echo "FAIL static check"; fail=1; else echo "ok"; fi

if swift scripts/shima-windows.swift --live-frame-only >/dev/null 2>&1; then live=1; else live=0; fi
if [[ $mode == growth ]]; then live=0; fi
if [[ $mode == idle && $live == 1 ]]; then echo "the island is live (Spotify playing); use --playing"; exit 2; fi
if [[ $mode == playing && $live == 0 ]]; then echo "the island is not live; start with SHIMA_FAKE_SPOTIFY=playing"; exit 2; fi
pid="$(pgrep -nx Shima)" || { echo "Shima is not running"; exit 2; }
secs() { ps -o time= -p "$1" | awk -F'[:.]' '{ print ($1*60 + $2) + ("0." $3) }'; }
pct() { awk -v a="$1" -v b="$2" -v n="$3" 'BEGIN { printf "%.3f", (b - a) / n * 100 }'; }
le() { awk -v v="$1" -v m="$2" 'BEGIN { exit !(v <= m) }'; }

measure_shima_60() {
  local t0 t1 cpu rss_kb
  t0="$(secs "$pid")"; echo "pid $pid, waiting 60 s; keep the pointer away from the notch"
  sleep 60
  t1="$(secs "$pid")"
  cpu="$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.3f", b - a }')"
  rss_kb="$(ps -o rss= -p "$pid" | tr -d ' ')"
  echo "cpu seconds used in 60 s: $cpu (pass <= $1)"
  le "$cpu" "$1" || { echo "FAIL cpu"; fail=1; }
  # Bar raised from 60 to 80 MB on 2026-11-23: the app sat at 55-59 MB fresh before the Calendar and Bluetooth features and
  # every interaction crosses 60. What matters is that it does not grow: see --growth.
  echo "rss: $((rss_kb / 1024)) MB (pass < 80; growth is checked by --growth)"
  (( rss_kb < 81920 )) || { echo "FAIL rss"; fail=1; }
  top -l 2 -s 3 -pid "$pid" -stats pid,cpu,idlew,threads | tail -1 | sed 's/^/top (pid cpu idlewakeups threads): /' || true
}
sample_check() {
  local out keep=0
  out="$(mktemp -t shima-sample)"
  sample "$pid" 3 -file "$out" >/dev/null 2>&1 || true
  if [[ ! -s "$out" ]]; then echo "sample: unavailable"
  elif grep -q '__CFRUNLOOP_IS_CALLING_OUT_TO_A_TIMER_CALLBACK_FUNCTION__' "$out"; then echo "FAIL sample shows a run loop timer firing ($out)"; fail=1; keep=1
  else echo "sample: no timer callbacks; main thread: $(grep -m1 -oE 'mach_msg2_trap|mach_msg_trap' "$out" || echo '?')"; fi
  (( keep )) || rm -f "$out"
}

if [[ $mode == growth ]]; then
  tools="$PWD/.build/tools"; mkdir -p "$tools"
  swiftc -O scripts/drive.swift -o "$tools/drive" >/dev/null 2>&1 || { echo "cannot build scripts/drive.swift"; exit 2; }
  d() { "$tools/drive" "$1" >/dev/null; }
  probe="$(mktemp -t shima-growth)"
  /usr/bin/log stream --level debug --style compact --predicate 'subsystem == "local.shima"' > "$probe" 2>&1 &
  lp=$!; sleep 1.5
  d "fake-calendar ping; fake-device bogus"; sleep 1; kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null || true
  cal=0; dev=0
  grep -q "Shima\[$pid:.*calendar fake ping" "$probe" && cal=1
  grep -q "Shima\[$pid:.*device fake bad command" "$probe" && dev=1
  rm -f "$probe"
  echo "pid $pid; fake calendar: $cal, fake devices: $dev (no Calendar clicks without the fake calendar)"
  read -r music camera header mid hover away mirrorX mirrorY pX pY playX playY nX nY artX artY calX rest < <(scripts/island-input-geometry.sh)
  rss_mb() { echo $(( $(ps -o rss= -p "$pid" | tr -d ' ') / 1024 )); }
  cycle() {
    local i="$1" steps="move $mid $away; sleep 200"
    (( dev )) && steps+="; fake-device connect|Growth $i|keyboard|-; sleep 400"
    steps+="; move $mid $hover; sleep 700"
    (( cal )) && steps+="; click-owned $pid $calX $header; sleep 300; click-owned $pid $music $header; sleep 250"
    steps+="; move $mid $away; sleep 1400"
    d "$steps"
  }
  # Launch grace (3 s) is over long before the first device event.
  base="$(rss_mb)"
  for i in 1 2 3 4 5; do cycle "$i"; done
  warm="$(rss_mb)"; echo "rss at launch ${base} MB, after 5 cycles ${warm} MB"
  for i in $(seq 6 20); do cycle "$i"; done
  sleep 3
  end="$(rss_mb)"; growth=$(( end - warm )); echo "rss after 20 cycles ${end} MB (grew ${growth} MB since cycle 5; pass < 6 MB growth and < 80 MB)"
  (( growth < 6 )) || { echo "FAIL rss keeps growing"; fail=1; }
  (( end < 80 )) || { echo "FAIL rss above 80 MB"; fail=1; }
  (( fail == 0 )) && echo "PASS growth" || { echo "FAIL growth"; exit 1; }
  exit 0
fi

if [[ $mode == idle ]]; then
  measure_shima_60 0.030
  sample_check
  (( fail == 0 )) && echo "PASS idle" || { echo "FAIL idle"; exit 1; }
  exit 0
fi

# --playing
dir="$(mktemp -d -t shima-idle)"; lp=""
trap '[[ -n "$lp" ]] && { kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null; }; rm -rf "$dir"' EXIT
/usr/bin/log stream --level debug --style compact --predicate 'subsystem == "local.shima"' > "$dir/log" 2>&1 &
lp=$!
sleep 1.5
swift scripts/drive.swift "fake ping" >/dev/null; sleep 1
if ! grep -q 'fake ping' "$dir/log"; then
  echo "not in fake mode: reporting Shima CPU only"
  measure_shima_60 0.060
  sample_check
  (( fail == 0 )) && echo "PASS playing" || { echo "FAIL playing"; exit 1; }
  exit 0
fi
ws="$(pgrep -nx WindowServer)" || { echo "WindowServer not found"; exit 2; }
n="${SHIMA_AB_SECONDS:-30}"
locked() { swift - <<'SW'
import CoreGraphics
let d = CGSessionCopyCurrentDictionary() as? [String: Any]
let v = d?["CGSSessionScreenIsLocked"]
print((v as? Bool) == true || (v as? Int) == 1 ? 1 : 0)
SW
}
last_eq() { grep -oE 'eq (animating anims=[0-9]+|frozen anims=0)' "$dir/log" | tail -1 || true; }
echo "load before: $(ps -Arcro %cpu=,comm= | head -5 | tr -s ' ' | paste -sd ';' -)"
echo "window ${n} s each (3 s settle); WindowServer pid $ws"
swift scripts/drive.swift "fake eq-frozen; sleep 400; fake eq-animating; sleep 400" >/dev/null
declare -a shima_a=() shima_f=() ws_a=() ws_f=()
invalid=0
run_phase() { # animating|frozen
  local ph="$1" want cmd s0 s1 w0 w1 lk0 lk1 l0 l1 ok=1
  if [[ $ph == animating ]]; then want='eq animating anims=4'; cmd='fake eq-animating'; else want='eq frozen anims=0'; cmd='fake eq-frozen'; fi
  swift scripts/drive.swift "$cmd" >/dev/null; sleep 3
  lk0="$(locked)"; l0="$(last_eq)"
  s0="$(secs "$pid")"; w0="$(secs "$ws")"
  sleep "$n"
  s1="$(secs "$pid")"; w1="$(secs "$ws")"
  lk1="$(locked)"; l1="$(last_eq)"
  [[ "$lk0" == 0 && "$lk1" == 0 && "$l0" == "$want" && "$l1" == "$want" ]] || ok=0
  local sp wp; sp="$(pct "$s0" "$s1" "$n")"; wp="$(pct "$w0" "$w1" "$n")"
  if (( ok )); then
    echo "  $ph: Shima ${sp}% WindowServer ${wp}% valid (locked=$lk0/$lk1, log='$l1')"
    if [[ $ph == animating ]]; then shima_a+=("$sp"); ws_a+=("$wp"); else shima_f+=("$sp"); ws_f+=("$wp"); fi
  else
    echo "  $ph: Shima ${sp}% WindowServer ${wp}% INVALID (locked=$lk0/$lk1, log before='$l0' after='$l1', wanted '$want')"
    invalid=1
  fi
}
for round in 1 2; do echo "round $round"; run_phase animating; run_phase frozen; done
sample_check
swift scripts/drive.swift "fake eq-animating" >/dev/null
echo "load after: $(ps -Arcro %cpu=,comm= | head -5 | tr -s ' ' | paste -sd ';' -)"
mean() { (( $# )) && printf '%s\n' "$@" | awk '{ s += $1 } END { printf "%.3f", s / NR }' || echo "nan"; }
sa="$(mean ${shima_a[@]+"${shima_a[@]}"})"; sf="$(mean ${shima_f[@]+"${shima_f[@]}"})"
wa="$(mean ${ws_a[@]+"${ws_a[@]}"})"; wf="$(mean ${ws_f[@]+"${ws_f[@]}"})"
if (( invalid )); then echo "INVALID: at least one window was not valid (screen locked or equalizer state not confirmed); numbers below use valid windows only"; fi
echo "Shima animating: ${sa}% (pass <= 0.100)"
echo "Shima frozen: ${sf}% (pass <= 0.050)"
[[ "$sa" != nan ]] && le "$sa" 0.100 || { echo "FAIL Shima animating"; fail=1; }
[[ "$sf" != nan ]] && le "$sf" 0.050 || { echo "FAIL Shima frozen"; fail=1; }
if [[ "$wa" != nan && "$wf" != nan ]]; then
  echo "WindowServer animating - frozen: $(awk -v a="$wa" -v f="$wf" 'BEGIN { printf "%.3f", a - f }')% (accepted cost: about +5 points at 20 fps; informational, WindowServer baseline is noisy)"
else echo "WindowServer animating - frozen: n/a"; fi
(( invalid )) && { echo "INVALID playing"; exit 3; }
(( fail == 0 )) && echo "PASS playing" || { echo "FAIL playing"; exit 1; }
