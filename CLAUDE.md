# shima

Personal macOS notch app (free Dynamic Island clone). Design: `docs/2026-11-20-notch-design.md`. Mockup (reference only, do not modify): `mockup/index.html`.

## Stack
Native Swift 6.1, SwiftPM, macOS 14+. SwiftUI views in a borderless non-activating `NSPanel`. Logic lives in `ShimaCore` (testable); `Shima` is the thin app; `shimactl` is the hook CLI.

## Commands
- `swift build` / `swift test`
- `scripts/bundle.sh` builds `dist/Shima.app` (ad-hoc signed); `scripts/run.sh` builds and launches it

## Rules
- **No Xcode.** Only Command Line Tools are installed. Everything must build with `swift build`; no `.xcodeproj`.
- No third-party dependencies without asking the user first.
- Do not touch `~/.claude/settings.json` or any file outside this repo.
- Use "shima" where the design doc says "notch" (`~/.config/shima/config.json`, `shimactl`).
- `shimactl` always exits 0 quickly. The panel never steals focus and uses no timers while idle.
- Put logic in `ShimaCore` with tests; keep AppKit glue in `Shima`.
- No tool-attribution trailers in commit messages (a hook enforces this).
