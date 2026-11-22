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
