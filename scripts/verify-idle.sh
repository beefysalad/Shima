#!/usr/bin/env bash
# Criterion 10: keep the pointer away from the notch for the whole run.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
echo "static check: no timers or event monitors in app code"
if grep -rnE 'addGlobalMonitorForEvents|addLocalMonitorForEvents|scheduledTimer|(^|[^A-Za-z])Timer[(.]|CVDisplayLink|repeatForever' Sources/Shima Sources/ShimaCore; then
  echo "FAIL static check"; fail=1; else echo "ok"; fi
pid="$(pgrep -x Shima)" || { echo "Shima is not running"; exit 2; }
secs() { ps -o time= -p "$pid" | awk -F'[:.]' '{ print ($1*60 + $2) + ("0." $3) }'; }
t0="$(secs)"; echo "pid $pid, waiting 60 s; keep the pointer away from the notch"
sleep 60
t1="$(secs)"
cpu="$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.3f", b - a }')"
rss_kb="$(ps -o rss= -p "$pid" | tr -d ' ')"
echo "cpu seconds used in 60 s: $cpu (pass <= 0.030, i.e. 0.0% average)"
awk -v c="$cpu" 'BEGIN { exit !(c <= 0.030) }' || { echo "FAIL cpu"; fail=1; }
echo "rss: $((rss_kb / 1024)) MB (pass < 60)"
(( rss_kb < 61440 )) || { echo "FAIL rss"; fail=1; }
top -l 2 -s 3 -pid "$pid" -stats pid,cpu,idlew,threads | tail -1 | sed 's/^/top (pid cpu idlewakeups threads): /'
out="$(mktemp -t shima-sample)"; sample "$pid" 3 -file "$out" >/dev/null 2>&1
if grep -q '__CFRUNLOOP_IS_CALLING_OUT_TO_A_TIMER_CALLBACK_FUNCTION__' "$out"; then echo "FAIL sample shows a run loop timer firing ($out)"; fail=1
else echo "sample: no timer callbacks; main thread: $(grep -m1 -oE 'mach_msg2_trap|mach_msg_trap' "$out" || echo '?')"; fi
(( fail == 0 )) && echo "PASS idle" || { echo "FAIL idle"; exit 1; }
