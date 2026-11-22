# Settings window acceptance record

## Decisions

- Date: 2026-11-22. macOS 26 (Darwin 25.6.0), ad-hoc dist build, fake Spotify mode.
- `activationStrategy = cooperative` (`NSApp.activate()` with `.accessory` throughout; no Dock icon). No fallback needed.
- Deciding log lines (Task 9 Step 3, reopen via `open dist/Shima.app` against the running dist pid):
  - `settings opened via reopen created=true active=true key=true`
  - `settings opened via reopen created=false active=true key=true`
- Focus on close: `settings closed policy=accessory restored=company.thebrowser.Browser active=false`; the frontmost app was the same before and after.
- Window list: `settings windows: 1` while open (one window, second reopen did not create another), `settings windows: 0` after Cmd-W.
- `app became active` is logged once per open (the one intended activation); it must stay absent for island interactions.
- Tasks 10 and 11 append the gear and menu entries' `active=`/`key=` results here.

## Task 10: gear entry (2026-11-22, fake mode, dist build)

- Pointer: hover notch, click gear at `889.5 50`. Log: `hover dwelling -> expanded`, `settings gear clicked active=false key=false`, `app became active` (the one intended activation), `settings opened via gear created=true active=true key=true`.
- Second gear open after Cmd-W: `settings opened via gear created=false active=true key=true`; `settings windows: 1` while open (window on the external display, x=2210), `settings windows: 0` after `key cmd-w`; `settings closed policy=accessory restored=company.thebrowser.Browser active=false`; frontmost app unchanged.
- `scripts/verify-view-layout.sh`: live black 0..<32 unchanged, `gear at (340.0, 38.0, 24.0, 24.0): glyph rows 43..<57 PASS`, no gear pixels collapsed.
- `scripts/verify-focus.sh --clicks` (window closed): `PASS clicks: 3 commands, frontmost unchanged`, no `app became active`.

## Task 11: status menu entry (2026-11-22, fake mode, dist build)

- Status item position logged at launch: `menu status item x=0.0 y=956.0 w=38.0 h=0.0`. Not on screen (y=956 is the bottom edge, h=0): the item is hidden on this Mac (full menu bar), so the menu click check is a SKIP, as design acceptance 7 allows. No x was guessed. The gear and re-launch entries cover this Mac; the `Settings…` menu item (`settings opened via menu`) is built and compiled but not exercised by a click here.
- Open question for a visible-item run: the frame is read in one `DispatchQueue.main.async` after creation; a hidden item and a not-yet-laid-out item look the same (zero height). If a future run with a visible item still logs h=0, read the frame later (for example in `menuNeedsUpdate`) instead.

## Launch at login and Automation button (Task 13)

Date 2026-11-22. Installed signed copy: `SHIMA_SIGN_ID=... scripts/install.sh` gave `Installed /Applications/Shima.app` with `designated => identifier "local.shima" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: jpatrickzephyr@gmail.com (<cert-id>)"` (no `cdhash`), no keychain prompt.

- **Script bug fixed:** `scripts/verify-settings.sh --login-item` reported "not signed with the Apple Development identity" although the signature was right: it piped `codesign -dvv` into `grep -q`, and under `pipefail` the early exit of `grep -q` failed the pipeline. It now captures the output first.
- **Launch at login (L2, L3 PASS):** status before `notRegistered`; register worked (`ok L2 register`) and the status read back `enabled` (`ok L3`). The user confirmed in System Settings > General > Login Items & Extensions that **Shima is listed** under Open at Login (no approval was needed).
- **L4/L5 FAIL, cause: the pause.** While the script waited at `--pause` the user had System Settings in front, so the script's synthetic click that should turn Launch at login off went to System Settings, not to Shima's window. The login item stayed ON (verified with the app: `settings refresh loginItem=enabled`). Recovery: Shima was re-activated with `open /Applications/Shima.app` and the same click repeated, which logged `settings loginItem toggle from=enabled action=unregister ok=true after=notRegistered`. Final state: **OFF** (`loginItem=notRegistered` in the next refresh). Follow-up: `--pause` should re-activate Shima (`open`) after the pause before clicking; until then the L4/L5 steps are verified by the recovery run.
- **Automation button (real, `dryRun=false`):** after relaunching the installed app without the dry-run switch, the window's "Open Automation Settings..." button logged `settings open url=x-apple.systempreferences:com.apple.preference.security?Privacy_Automation dryRun=false` and the user confirmed System Settings opened at **Privacy & Security > Automation**. The log line appeared twice for the one reported click; harmless, but note it (a second click or a double dispatch).
- **Signing text:** `signing="Apple Development certificate expires 2027-03-26"`, `version="Version 0.0.1 (1)"`.
- **Also seen:** one `settings opened via menu created=false active=false key=false` line during this run (the Settings... menu entry fired once; its activation was logged before the app became active).
- **sfltool:** not run (needs no admin by default but is optional; the System Settings list and the status readback were used).
- The window opens on the external display here (x=2210, y=67, w=440, h=408).

## Acceptance run (Task 14)

Date 2026-11-22. macOS 26 (Darwin 25.6.0), Swift 6.4.2, built-in display 1470x956 (notch 646,0,179x32), build from commit `30a63c4` (the uncommitted `assets/branding/*` and `scripts/bundle.sh` changes are the user's icon work and were not touched). `swift test`: **285 tests in 21 suites passed** (the plan text says 270; the count grew with later tasks). Fresh `scripts/bundle.sh` gave `Built dist/Shima.app`, ad-hoc signed, FAKE mode only (`SHIMA_FAKE_SPOTIFY`, no `SHIMA_SIGN_ID`, no real mode). `/Applications/Shima.app` was neither run nor modified; the final install (Task 14 Step 4) is not part of this run. Spotify was not running at the start or the end of this run (`pgrep -lx Spotify` empty both times); nothing was sent to it.

How evidence was gathered: fake mode, CGEvent input (`scripts/drive.swift`), `os.Logger` lines (`scripts/with-log.sh`), the window list (`scripts/shima-windows.swift`) and the offscreen render of `scripts/view-layout-check.swift`; no screenshots. CPU rows used `caffeinate -dimsu`, the screen was unlocked (`CGSSessionScreenIsLocked` absent), CPU is Shima's own `ps` time. Raw output is in `.build/s14/` (not committed). Pointer-driven time in total: about 1.5 minutes (verify-settings about 25 s, focus clicks, live hover, one expanded-frame hover).

### Design acceptance criteria

| # | Criterion (design) | Result | Kind | Evidence and notes |
|---|---|---|---|---|
| 1 | Each entry opens the same single window | **PASS** (entry 3 SKIP) | AUTOMATED; window on external display HUMAN | `verify-settings.sh` A1/A2 (reopen opens it active and key, second reopen reuses it, `1 window`), C2/C3 (gear opens the same window, second gear click reuses it), D1 closed to `0 window`. D (status menu entry) SKIP: `menu status item x=0.0 y=956.0 w=38.0 h=0.0`, the capsule is hidden on this Mac; the `Settings...` click was not exercised (one `settings opened via menu` line was seen in Task 13). The user saw the window open on the external display |
| 2 | Launch at login toggles and matches System Settings, ends OFF | **PASS** | AUTOMATED + HUMAN | Task 13 (see above): `register` then status `enabled`, user saw Shima listed in System Settings > Login Items; the first L4/L5 script click went to System Settings (pause), recovery run logged `action=unregister ok=true after=notRegistered`; final OFF. `sfltool` not run. Not re-run in this task (signed copy only) |
| 3 | Quit ends the process | **PASS** | AUTOMATED | `verify-settings.sh` G2: `quit logged`, `Quit ends the process` |
| 4 | Spotify rows in fake mode, URL logged | **PASS** | AUTOMATED + HUMAN | F1 notRunning, F2 running, F3 permissionDenied, F4 button logs the Automation URL (dry run), F5 running again. HUMAN: the real Automation button opened Privacy & Security > Automation (Task 13) |
| 5 | Equalizer mode persists and changes the wings | **PASS** | AUTOMATED | E0-E5 (`animated`, `off` frozen, `whenOpen`: collapsed frozen, open island animates, back to `animated`), G1-G7 (mode `off` survives a relaunch, wings still, `animated` saved and animating, `defaults read local.shima equalizerMode` = `animated`) |
| 6 | Back to `.accessory`, island as before | **PASS with one WARN** | AUTOMATED | B1/B2/G8 (policy `accessory`, frontmost app restored: `company.thebrowser.Browser`), `verify-focus.sh --clicks` `PASS clicks: 3 commands, frontmost unchanged: Arc`, `verify-live-hover.sh` `PASS live hover` (dwell 92 ms, debounce 317 ms), strict idle PASS on a fresh paused instance (see the WARN under Idle) |
| 7 | Works with the menu bar full | **PASS** | AUTOMATED | Entries 1 (reopen) and 2 (gear) pass independently of the status item; D is a SKIP with the logged item frame |
| - | Version and certificate expiry shown | **PASS** | AUTOMATED | Task 9 Step 3 (dist: ad hoc), Task 13 (signed: `Version 0.0.1 (1)`, `Apple Development certificate expires 2027-03-26`) |

### M1 regression checks (fresh dist build, fake mode)

| M1 row | Check | Result | Evidence |
|---|---|---|---|
| 2a | Controls, no focus steal | **PASS** | `scripts/verify-focus.sh --clicks`: `PASS clicks: 3 commands, frontmost unchanged: Arc` (it also ran in `verify-settings.sh` B2) |
| 3, 4, 5 (M0) | Hover, dwell, collapse, one frame change per transition | **PASS** | `scripts/verify-live-hover.sh`: all A-H lines `ok`, `dwell 92 ms (want 60-150), debounce 317 ms (want 280-420)`, `PASS live hover`. Note the script leaves the instance playing; a `fake paused` was needed before the idle check |
| 1 (M0) | Alignment, not live | **PASS** | `window layer=25 x=646 y=0 w=179 h=32`, `PASS idle frame matches notch within 1pt` (also after the window was opened and closed) |
| 4a | Alignment, live | **PASS (WARN accepted)** | `window x=613 y=0 w=245 h=32`, `PASS live frame matches notch+wings within 1pt`; `WARN wings overlap first status item by 2pt (item windows include padding; check by eye)`: same accepted warning as M1 (then 3-4 pt) |
| - | Alignment, expanded | **PASS** | `window x=537 y=0 w=396 h=173`, `PASS expanded frame matches layout within 1pt` |
| - | `verify-view-layout.sh` | **PASS** | live 245x32 black 0..<32, artwork 6..<26, equalizer 9..<23; `gear at (340.0, 38.0, 24.0, 24.0): glyph rows 43..<57 PASS`; expanded 396x173 silhouette 0..<165 with the equalizer shown with a track and hidden without; not-live 179x32 PASS |
| 10 | Strict idle, fresh paused instance | **PASS** | `ok` static check, `cpu seconds used in 60 s: 0.000 (pass <= 0.030)`, rss 53 MB (< 60), `sample: no timer callbacks; main thread: mach_msg2_trap`, `PASS idle` |
| 10 | Strict idle after the Settings window was opened and closed (the plan's batch 4 order) | **FAIL (rss), CPU PASS** | cpu 0.000 s in 60 s, but `rss: 65 MB (pass < 60)` and, in that one run, `sample shows a run loop timer firing`: the stack was AppKit's `NSStatusItem _updateReplicantsUnlessMenuIsTracking:` (`__NSFireDelayedPerform`), not Shima code; three more 3 s samples on the same instance (and the fresh-instance run) showed no timer. Details below |
| 7 | CPU, `--playing` | **SKIP** | Not run: it needs about 2.5 minutes of A/B windows. Covered by M1's measurement (animating and frozen at 20 fps, accepted) plus the Task 8 equalizer mode tests and E0-E5/G4/G6 here (frozen and animating confirmed by `eq frozen`/`eq animating` log lines) |
| 3, 5, 6, 8 and the HUMAN rows 1, 2b, 4b | Fake quit, progress ticks, typing, Automation survives a rebuild, real Spotify | **NOT RE-RUN** | Not part of this run; the M1 results stand. Typing and Apple menu were re-checked in M1 |

### Failures, warnings and follow-ups

1. **RSS after opening the Settings window (FAIL against the plan's order, new finding).** A fresh paused dist instance idles at about 53-57 MB RSS and passes `rss < 60`. After one open and close of the Settings window RSS is 65-69 MB (measured 67104 kB, then 69120, 68992 and 65360 kB over 10 s after a second instance's open/close), and `verify-idle.sh` fails on `rss`. CPU stays 0.000 s. Cause is probably the SwiftUI/AppKit memory a settings window pulls in (framework pages, hosting view) and is not returned; whether the window or its hosting view is released on close was not checked. Not fixed, since the script threshold is the plan's: either accept the figure (+12 MB once the window has been opened) and raise the threshold for post-Settings runs, or release the window on close. This is for the controller to decide.
2. **One transient timer callback in a sample.** In the first idle run after the window had been opened, `sample` caught an AppKit status item replicant redraw (`NSStatusItem _updateReplicant`) in a run loop timer. It did not repeat in three more samples or in the fresh-instance run. No timer exists in Shima's sources (static check `ok`). Treated as a one-off after a window open (the item is hidden on this Mac), not reproduced; worth a re-look if idle ever shows it again.
3. **Status menu entry (D) not exercised**, as agreed (capsule hidden). `Settings...` via the menu is therefore HUMAN-untested here.
4. `verify-live-hover.sh` leaves a paused instance live; `verify-idle.sh` then refuses (`the island is live`). Run `fake paused` between them. Not changed.
5. Task 13 follow-ups still stand: `--pause` should re-activate Shima before clicking, and the Automation button logged its line twice for one click.
