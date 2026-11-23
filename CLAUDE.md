# shima

Personal macOS notch app (free Dynamic Island clone). Design: `docs/2026-11-20-notch-design.md` (section 8 is the M1 Spotify design). Mockup: `mockup/index.html` is the approved visual reference; the real UI must match it, and UI changes start by updating it.

## Status
M0 (island shell), M1 (Spotify), the Settings window and the Camera tab are built, reviewed and accepted (records in `docs/superpowers/*-acceptance.md`). The Calendar and Reminders tab and the Bluetooth device banner (built on a new peek phase in the hover machine) are merged on `main` with their automated checks passing; their hands-on checks (permission prompts, real calendars, real AirPods and keyboard) are open, see `calendar-acceptance.md` and `device-popups-acceptance.md`. The shelf (a real Home tab, a drag veil on any tab, drop files, text and links onto the island, drag them back out) and the Settings gear moved to the right wing are built on branch `shelf` with automated checks passing (`scripts/verify-shelf.sh`, fake shelf `SHIMA_FAKE_SHELF=1`); the real-drag checks are open, see `shelf-acceptance.md`. M2, Claude Code session state, is parked for later. Still open from M0: the external-monitor and clamshell checks (criterion 8). `shimactl` is a stub until M2.

## Stack
Native Swift (6.4.2 toolchain, Xcode 27.2), SwiftPM, macOS 14+. SwiftUI views in a borderless non-activating `NSPanel`. Logic lives in `ShimaCore` (testable); `Shima` is the thin app; `shimactl` is the hook CLI.

## Commands
- `swift build` / `swift test` (Swift Testing, `import Testing`; no XCTest)
- `scripts/bundle.sh` builds `dist/Shima.app` (ad-hoc signed unless `SHIMA_SIGN_ID` is set); `scripts/run.sh` builds and launches it, stopping only this checkout's `dist` instance by pid
- `SHIMA_SIGN_ID='Apple Development: <you> (<cert-id>)' scripts/install.sh [--open]` installs to `/Applications/Shima.app` (refuses an ad-hoc rebuild over a certificate-signed install, because that would lose the Spotify Automation grant); `scripts/package.sh` writes `dist/Shima-<version>.zip`
- Fake Spotify for tests: `SHIMA_FAKE_SPOTIFY=playing|paused scripts/run.sh`, then `swift scripts/drive.swift "fake <cmd>"` (ping, playing, paused, next, previous, quit, launch, denied, allowed, eq-mode-animated|whenOpen|off, eq-frozen, eq-animating). `run.sh` refuses real mode without `SHIMA_SIGN_ID`.
- Fake services for tests: `SHIMA_FAKE_CALENDAR=1` (`drive.swift "fake-calendar <cmd>"`: ping, allowed, denied, empty, full, changed, daychanged), `SHIMA_FAKE_DEVICES=1` (`drive.swift "fake-device connect|<name>|<kind>|<battery or ->"`), `SHIMA_FAKE_CAMERA=1`. Pointer checks must not run while another Shima (the installed one) overlaps: `click-owned PID X Y` refuses a click unless our process owns the window, and `SHIMA_WINDOW_PID` / a pid argument limits `shima-windows.swift` to one process.
- Checks (need the app running): `scripts/verify-alignment.sh [--live|--expanded|--menus]`, `verify-focus.sh [--clicks]`, `verify-live-hover.sh`, `verify-idle.sh [--playing|--growth]` (RSS bar is 80 MB plus flat growth over 20 open/close cycles), `verify-calendar.sh` (fresh fake-calendar process), `verify-peek.sh`, `verify-settings.sh`, `verify-view-layout.sh`, `watch-hover.sh`. `drive.swift` injects pointer and key events; `shima-windows.swift` lists windows; `with-log.sh` captures the `local.shima` log.
- Logs: `/usr/bin/log stream --level debug --predicate 'subsystem == "local.shima"'` (zsh's `log` is a builtin).

## Rules
- **SwiftPM only, no `.xcodeproj`.** Xcode (27.2) is installed, but everything must build with `swift build` / `swift test`. This is a project choice, not a tooling limit.
- No third-party dependencies without asking the user first.
- Do not touch `~/.claude/settings.json` or any file outside this repo (the one approved exception: `/Applications/Shima.app` via `scripts/install.sh`).
- Use "shima" where the design doc says "notch" (`~/.config/shima/config.json`, `shimactl`).
- `shimactl` always exits 0 quickly. The island panel never steals focus (the only intended activation is opening the Settings window) and uses no timers or polling while idle; Spotify state is event-driven.
- Put logic in `ShimaCore` with tests; keep AppKit glue in `Shima`. `ShimaCore` must not import AppKit.
- No tool-attribution trailers in commit messages (a hook enforces this). Stage explicit paths, never `git add -A`.
- Never launch, quit or command the user's Spotify in tests or scripts: use fake mode. Never use `NSAppleScript`, `tell application` or any launch API for Spotify: Apple Events go by pid on a private serial queue, and a dead pid must return -600.
- Never `pkill -x Shima` (it kills the installed app and other worktrees' runs): check `pgrep -lx Shima` / `ps -o command= -p <pid>` and kill by pid.
- Never commit signing identifiers (team id, certificate id); docs use placeholders. The real identity lives in the `SHIMA_SIGN_ID` environment variable. The repo is public.
- Do not commit build caches (`.build`, `dist`); delete them when the user asks.

## Gotchas learned
- A hidden SwiftUI view still takes part in layout: nothing may enlarge the island's root `ZStack`; use overlays or explicit frames. `scripts/verify-view-layout.sh` renders the views offscreen and checks pixels (black 0..32 live, 0..<165 expanded).
- Resizing the panel makes macOS re-send `mouseEntered`; a collapse completion can arrive after a re-expand (generation numbers handle both).
- Spotify posts no broadcast for a same-track Previous, and its script state lags its broadcast: a script read must never override a broadcast state (see the position-only follow-up in `SpotifyCoordinator`).
- The equalizer only animates while its window is visible: a locked or sleeping screen invalidates CPU runs; use `caffeinate -dimsu` and check the lock state.
- `SMAppService` reports `notFound` before the first registration (normal). Launch at login only works from `/Applications`.
- The terminal has no Screen Recording permission: verify with logs, the window list, CGEvent input and offscreen `cacheDisplay` renders, not screenshots.
- `grep -q` at the end of a pipe under `set -o pipefail` can fail wrongly: capture the output first.

## Working style
- Milestones each have a spec, a plan and an acceptance record under `docs/superpowers/` (`specs/`, `plans/`, `spikes/`). Plans split work into PURE (ShimaCore, parallel-safe for a second engineer in its own worktree under `.worktrees/`), GLUE, SCRIPT and HUMAN tasks. Fresh implementer plus separate reviewer per task; one whole-branch review at the end.
- Keep pointer-driven checks short (about 1–2 minutes) and announce them; do not ask the user to stay hands-off for long runs.
