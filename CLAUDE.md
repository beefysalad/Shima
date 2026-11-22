# shima

Personal macOS notch app (free Dynamic Island clone). Design: `docs/2026-11-20-notch-design.md`. Mockup (reference only, do not modify): `mockup/index.html`.

## Stack
Native Swift (6.4.2 toolchain, Xcode 27.2), SwiftPM, macOS 14+. SwiftUI views in a borderless non-activating `NSPanel`. Logic lives in `ShimaCore` (testable); `Shima` is the thin app; `shimactl` is the hook CLI.

## Commands
- `swift build` / `swift test`
- `scripts/bundle.sh` builds `dist/Shima.app` (ad-hoc signed); `scripts/run.sh` builds and launches it

## Rules
- **SwiftPM only, no `.xcodeproj`.** Xcode (27.2) is now installed, but everything must still build with `swift build` / `swift test`. This is a project choice, not a tooling limit.
- No third-party dependencies without asking the user first.
- Do not touch `~/.claude/settings.json` or any file outside this repo.
- Use "shima" where the design doc says "notch" (`~/.config/shima/config.json`, `shimactl`).
- `shimactl` always exits 0 quickly. The panel never steals focus and uses no timers while idle.
- Put logic in `ShimaCore` with tests; keep AppKit glue in `Shima`.
- No tool-attribution trailers in commit messages (a hook enforces this).
