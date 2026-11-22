#!/usr/bin/env bash
# Settings window checks (design 2026-11-22, acceptance 1-6). Fake mode only; never touches Spotify.
# Announce before running: about 60-90 s of synthetic pointer and key input.
#   scripts/verify-settings.sh [--replace]
#       dist/Shima.app: three entries and one window, close and focus, equalizer modes,
#       persistence across a relaunch, Spotify rows and the Automation URL, Quit.
#       The test instance is left running (the M1 checks need it); with --stop it is stopped at the end.
#       The stored equalizerMode is restored on exit once the instance has stopped.
#   scripts/verify-settings.sh --login-item [--pause] [--replace]
#       /Applications/Shima.app (signed): Launch at login on, read back, off (ends OFF)
# Launches its own Shima and kills only that pid. --replace stops a Shima running from /Applications
# or this checkout's dist first (by pid) and does not restart it.
set -uo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
login=0; pause=0; replace=0; stop=0
for a in "$@"; do
  case "$a" in
    --login-item) login=1 ;; --pause) pause=1 ;; --replace) replace=1 ;; --stop) stop=1 ;;
    *) echo "unknown argument: $a"; exit 2 ;;
  esac
done
if (( login )); then APP="/Applications/Shima.app"; else APP="$REPO/dist/Shima.app"; fi
BIN="$APP/Contents/MacOS/Shima"
[[ -x "$BIN" ]] || { echo "missing $BIN (scripts/bundle.sh, or scripts/install.sh for --login-item)"; exit 2; }
H=380                                   # SettingsLayout.size.height
N="735 16"; A="735 400"; GEAR="889.5 50" # NowPlayingLayout.settingsButtonCenter on this Mac
SEG_animated="185 108"; SEG_whenOpen="275 108"; SEG_off="365 108"   # SettingsLayoutTests pins these
LOGIN="28 50"; AUTOMATION="135 240"; QUIT="370 352"
dir="$(mktemp -d -t shima-settings)"; fail=0; pid=""; lp=""; cf=""; LAUNCH_MARK=0
wx=0; wy=0; ww=0; wh=0
tools="$REPO/.build/tools"; mkdir -p "$tools"
swiftc -O scripts/drive.swift -o "$tools/drive" >/dev/null 2>&1 || { echo "cannot build scripts/drive.swift"; exit 2; }
swiftc -O scripts/shima-windows.swift -o "$tools/shima-windows" >/dev/null 2>&1 || { echo "cannot build scripts/shima-windows.swift"; exit 2; }
d() { "$tools/drive" "$1" >/dev/null; }
front() { lsappinfo info -only bundleid "$(lsappinfo front)" | sed -E 's/.*="(.*)"/\1/'; }

others="$(pgrep -x Shima || true)"
if [[ -n "$others" ]]; then
  if (( replace )); then
    for p in $others; do
      cmd="$(ps -o command= -p "$p" || true)"
      case "$cmd" in
        /Applications/Shima.app/*|"$REPO/dist/Shima.app/"*) echo "stopping Shima pid $p ($cmd)"; kill "$p" ;;
        *) echo "Shima pid $p runs from elsewhere ($cmd); quit it first"; exit 2 ;;
      esac
    done
    for _ in $(seq 20); do pgrep -x Shima >/dev/null || break; sleep 0.2; done
  else
    echo "Shima is already running:"; for p in $others; do ps -o pid=,command= -p "$p"; done
    echo "quit it, or pass --replace to stop it by pid (it is not restarted)"; exit 2
  fi
fi
orig="$(front)"
orig_eq="$(defaults read local.shima equalizerMode 2>/dev/null || echo none)"
cleanup() {
  [[ -n "$lp" ]] && { kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null; }
  [[ -n "$cf" ]] && kill "$cf" 2>/dev/null
  # Put the user's stored equalizerMode back, but only once no instance of ours can write it again.
  if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
    if [[ "$orig_eq" == none ]]; then defaults delete local.shima equalizerMode 2>/dev/null || true
    else defaults write local.shima equalizerMode -string "$orig_eq" 2>/dev/null || true; fi
  fi
  [[ -n "$orig" && "$orig" != local.shima && "$(front)" != "$orig" ]] && open -b "$orig"
}
trap cleanup EXIT
caffeinate -dimsu & cf=$!
/usr/bin/log stream --level debug --style compact --predicate 'subsystem == "local.shima"' > "$dir/all.log" 2>&1 & lp=$!
sleep 1.5

mark() { wc -l < "$dir/all.log" | tr -d ' '; }
since() { tail -n +"$(( $1 + 1 ))" "$dir/all.log"; }
has() { grep -qE -- "$2" <(since "$1"); }
wait_for() { local i; for (( i = 0; i < ${3:-30}; i++ )); do has "$1" "$2" && return 0; sleep 0.1; done; return 1; }
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1${2:+ ($2)}"; fail=1; }
expect_log() { if wait_for "$2" "$3" "${4:-30}"; then ok "$1"; else bad "$1" "no '$3'"; return 1; fi; }
last_eq() { grep -oE 'eq (animating anims=[0-9]+|frozen anims=0)' "$dir/all.log" | tail -1 || true; }
expect_eq() { sleep 0.4; if [[ "$(last_eq)" == "$2" ]]; then ok "$1"; else bad "$1" "last '$(last_eq)', want '$2'"; fi; }
windows() { "$tools/shima-windows" --settings "$pid" | sed -nE 's/^settings windows: ([0-9]+)$/\1/p'; }
expect_windows() { local n; n="$(windows)"; if [[ "$n" == "$2" ]]; then ok "$1 ($n window)"; else bad "$1" "settings windows: $n, want $2"; fi; }
wrect() {
  local line; line="$("$tools/shima-windows" --settings "$pid" | sed -nE 's/^settings window x=(-?[0-9]+) y=(-?[0-9]+) w=([0-9]+) h=([0-9]+)$/\1 \2 \3 \4/p' | head -1)"
  [[ -n "$line" ]] || return 1; read -r wx wy ww wh <<< "$line"
}
shima_front() { local i; for (( i = 0; i < 30; i++ )); do [[ "$(front)" == local.shima ]] && return 0; sleep 0.1; done; return 1; }
wclick() { # never click unless Shima is frontmost, so a click cannot land on System Settings
  if [[ "$(front)" != local.shima ]]; then
    open "$APP"
    shima_front || { bad "click guard" "Shima is not frontmost (front $(front)); click skipped"; return 1; }
    sleep 0.3; wrect || return 1
  fi
  set -- $1; d "click $(( wx + $1 )) $(( wy + wh - H + $2 ))"; }
reopen() { local m; m="$(mark)"; open "$APP"; wait_for "$m" 'settings opened via reopen .*active=true key=true' 40; sleep 0.3; wrect; }
launch() { # KEY=VALUE...
  local m a=() kv p; m="$(mark)"
  for kv in "$@"; do a+=(--env "$kv"); done
  open "${a[@]}" "$APP"
  pid=""
  for _ in $(seq 50); do
    for p in $(pgrep -x Shima || true); do [[ "$(ps -o command= -p "$p" || true)" == "$BIN"* ]] && pid="$p"; done
    [[ -n "$pid" ]] && break; sleep 0.1
  done
  [[ -n "$pid" ]] || { echo "Shima did not start"; exit 2; }
  wait_for "$m" 'spotify mode fake' 50 || { echo "Shima pid $pid is not in fake mode; stopping it"; kill "$pid"; exit 2; }
  LAUNCH_MARK="$m"
}
stop_own() { [[ -n "$pid" ]] || return 0; kill "$pid" 2>/dev/null; for _ in $(seq 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done; }
locked() { swift - <<'SW'
import CoreGraphics
let d = CGSessionCopyCurrentDictionary() as? [String: Any]
let v = d?["CGSSessionScreenIsLocked"]
print((v as? Bool) == true || (v as? Int) == 1 ? 1 : 0)
SW
}

if (( login )); then
  sig="$(codesign -dvv "$APP" 2>&1 || true)"   # capture first: `grep -q` closing the pipe early fails under pipefail
  grep -q '^Authority=Apple Development' <<< "$sig" \
    || { echo "$APP is not signed with the Apple Development identity (SHIMA_SIGN_ID=... scripts/install.sh)"; exit 2; }
  launch SHIMA_FAKE_SPOTIFY=paused SHIMA_SETTINGS_DRY_OPEN=1
  m="$(mark)"; reopen || bad "L1 window bounds"
  before="$(since "$m" | grep -oE 'settings refresh loginItem=[A-Za-z]+' | tail -1 | sed 's/.*=//')"
  echo "     Launch at login before: ${before:-unknown}"
  [[ "$before" != enabled ]] || { echo "Launch at login is already ON; turn it off in the window, then re-run"; exit 2; }
  m="$(mark)"; wclick "$LOGIN"
  expect_log "L2 register" "$m" "settings loginItem toggle from=$before action=register ok=true after=enabled"
  if (( pause )); then
    read -r -p "Launch at login is ON: check System Settings > General > Login Items & Extensions, then press Return " _
  fi
  m="$(mark)"; reopen
  expect_log "L3 status reads back enabled" "$m" 'settings refresh loginItem=enabled'
  m="$(mark)"; wclick "$LOGIN"
  expect_log "L4 unregister" "$m" 'settings loginItem toggle from=enabled action=unregister ok=true after=notRegistered' \
    || echo "!!!! Launch at login is still ON: turn it off in Shima's Settings window (or System Settings > General > Login Items) !!!!"
  m="$(mark)"; reopen
  expect_log "L5 ends OFF" "$m" 'settings refresh loginItem=notRegistered'
  d "key cmd-w"; sleep 0.5
  stop_own
  echo "stopped the test instance (pid $pid); /Applications/Shima.app is not running"
  (( fail == 0 )) && { echo "PASS login item"; exit 0; } || { echo "FAIL login item ($dir)"; exit 1; }
fi

launch SHIMA_FAKE_SPOTIFY=playing SHIMA_SETTINGS_DRY_OPEN=1
echo "Shima pid $pid (fake playing); driving pointer and keys for about a minute"
echo "     $(since "$LAUNCH_MARK" | grep -oE 'settings eq mode=[A-Za-z]+ loaded' | tail -1)"

# A. Reopen (entry 1) and one window
m="$(mark)"; open "$APP"
expect_log "A1 reopen opens the window, active and key" "$m" 'settings opened via reopen created=true active=true key=true'
expect_windows "A1 one window" 1
wrect && [[ "$ww" == 440 ]] && ok "A1 window width 440" || bad "A1 window bounds" "x=$wx y=$wy w=$ww h=$wh"
if ! has "$LAUNCH_MARK" 'settings eq mode=animated loaded'; then wclick "$SEG_animated"; sleep 0.5; fi
m="$(mark)"; open "$APP"
expect_log "A2 second reopen reuses it" "$m" 'settings opened via reopen created=false'
expect_windows "A2 still one window" 1

# B. Close: accessory, focus back
m="$(mark)"; d "key cmd-w"
expect_log "B1 closed, policy accessory" "$m" 'settings closed policy=accessory'
sleep 0.3; expect_windows "B1 no window" 0
now="$(front)"; if [[ "$now" == "$orig" ]]; then ok "B2 focus back to $orig"; else bad "B2 focus back" "frontmost $now, want $orig"; open -b "$orig"; fi
echo "     lsappinfo: $(lsappinfo info -only ApplicationType "$(lsappinfo find pid="$pid")" 2>/dev/null)"

# C. Gear (entry 2)
m="$(mark)"; d "move $A; sleep 400; move $N; sleep 700; click $GEAR; sleep 700"
expect_log "C1 gear click on the non-key panel" "$m" 'settings gear clicked active=false key=false'
expect_log "C2 gear opens the same window, active and key" "$m" 'settings opened via gear created=false active=true key=true'
d "move $A; sleep 1200"
expect_windows "C2 one window" 1
m="$(mark)"; d "move $N; sleep 700; click $GEAR; sleep 700; move $A; sleep 1200"
expect_log "C3 second gear click reuses it" "$m" 'settings opened via gear created=false'
expect_windows "C3 still one window" 1

# D. Status menu (entry 3), when the item is visible
item="$(grep -oE 'menu status item x=-?[0-9.]+ y=-?[0-9.]+ w=[0-9.]+ h=[0-9.]+' "$dir/all.log" | tail -1)"
sx="${SHIMA_STATUS_ITEM_X:-}"
if [[ -z "$sx" && -n "$item" ]]; then
  sx="$(echo "$item" | awk '{ for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] } } END { if (v["x"] >= 0 && v["x"] < 1470 && v["h"] > 0 && v["y"] < 40) printf "%.0f", v["x"] + v["w"] / 2 }')"
fi
if [[ -z "$sx" ]]; then
  echo "SKIP D status item not on the built-in menu bar (${item:-no status item line}); entries 1 and 2 cover a full menu bar"
else
  d "click $sx 16; sleep 500"
  menu="$("$tools/shima-windows" --menus | sed -nE 's/^menu window owner=Shima x=(-?[0-9]+) y=(-?[0-9]+) w=([0-9]+) h=([0-9]+)$/\1 \2 \3 \4/p' | head -1)"
  if [[ -z "$menu" ]]; then
    d "key esc"; echo "SKIP D no Shima menu after a click at x=$sx (item hidden or moved; set SHIMA_STATUS_ITEM_X)"
  else
    read -r mx my mw mh <<< "$menu"
    m="$(mark)"; d "move $(( mx + 40 )) $(( my + 16 )); sleep 150; click $(( mx + 40 )) $(( my + 16 )); sleep 700"
    expect_log "D1 status menu Settings… opens the same window" "$m" 'settings opened via menu created=false'
    expect_windows "D1 one window" 1
  fi
fi

# E. Equalizer modes (live, collapsed, fake playing)
if [[ "$(locked)" == 1 ]]; then bad "E screen unlocked" "the screen is locked; equalizer checks are invalid"; fi
reopen || bad "E window bounds"
expect_eq "E0 live wings animate (animated)" 'eq animating anims=4'
m="$(mark)"; wclick "$SEG_off"; expect_log "E1 mode off saved" "$m" 'settings eq mode=off saved'
expect_eq "E1 live wings frozen" 'eq frozen anims=0'
m="$(mark)"; wclick "$SEG_whenOpen"; expect_log "E2 mode whenOpen saved" "$m" 'settings eq mode=whenOpen saved'
expect_eq "E2 collapsed stays frozen" 'eq frozen anims=0'
d "move $N; sleep 900"; expect_eq "E3 open island animates" 'eq animating anims=4'
d "move $A; sleep 1500"; expect_eq "E4 collapsed again, frozen" 'eq frozen anims=0'
reopen
m="$(mark)"; wclick "$SEG_animated"; expect_log "E5 mode animated saved" "$m" 'settings eq mode=animated saved'
expect_eq "E5 live wings animate" 'eq animating anims=4'

# F. Spotify rows and the Automation button
m="$(mark)"; d "fake quit"; expect_log "F1 row notRunning" "$m" 'settings spotify row=notRunning'
m="$(mark)"; d "fake launch"; expect_log "F2 row running" "$m" 'settings spotify row=running'
m="$(mark)"; d "fake denied"; expect_log "F3 row permissionDenied" "$m" 'settings spotify row=permissionDenied'
reopen
m="$(mark)"; wclick "$AUTOMATION"
expect_log "F4 button logs the Automation URL (dry run)" "$m" 'settings open url=x-apple\.systempreferences:com\.apple\.preference\.security\?Privacy_Automation dryRun=true'
m="$(mark)"; d "fake allowed"; expect_log "F5 row running again" "$m" 'settings spotify row=running'
d "fake playing"; sleep 0.5

# G. Persistence across a relaunch, and Quit
reopen
m="$(mark)"; wclick "$SEG_off"; expect_log "G1 mode off saved" "$m" 'settings eq mode=off saved'
old="$pid"; m="$(mark)"; wclick "$QUIT"
expect_log "G2 quit logged" "$m" 'settings quit'
gone=0; for _ in $(seq 30); do kill -0 "$old" 2>/dev/null || { gone=1; break; }; sleep 0.1; done
if (( gone )); then ok "G2 Quit ends the process"; else bad "G2 Quit ends the process" "pid $old still running"; kill "$old"; fi
launch SHIMA_FAKE_SPOTIFY=playing SHIMA_SETTINGS_DRY_OPEN=1
expect_log "G3 mode off loaded after relaunch" "$LAUNCH_MARK" 'settings eq mode=off loaded'
expect_log "G3 island live" "$LAUNCH_MARK" 'spotify live true'
sleep 1.5
if has "$LAUNCH_MARK" 'eq animating'; then bad "G4 wings stay still with mode off" "eq animating after relaunch"; else ok "G4 wings stay still with mode off"; fi
m="$(mark)"; open "$APP"
expect_log "G5 window after relaunch" "$m" 'settings opened via reopen created=true'
sleep 0.3; wrect || bad "G window bounds"
m="$(mark)"; wclick "$SEG_animated"; expect_log "G6 mode animated saved" "$m" 'settings eq mode=animated saved'
expect_eq "G6 wings animate" 'eq animating anims=4'
stored="$(defaults read local.shima equalizerMode 2>/dev/null || echo none)"
if [[ "$stored" == animated ]]; then ok "G7 stored equalizerMode=animated"; else bad "G7 stored equalizerMode" "$stored"; fi
m="$(mark)"; d "key cmd-w"; expect_log "G8 closed, policy accessory" "$m" 'settings closed policy=accessory'

[[ "$(front)" == "$orig" ]] || open -b "$orig"
if (( stop )); then stop_own; echo "stopped the test instance (pid $pid)"
else echo "Shima pid $pid left running (fake playing, Settings closed) for the M1 checks; stop it with: kill $pid"; fi
(( fail == 0 )) && echo "PASS settings" || { echo "FAIL settings ($dir)"; exit 1; }
