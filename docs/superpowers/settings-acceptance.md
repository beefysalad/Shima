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
