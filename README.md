<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/branding/shima-logo.svg">
    <img src="assets/branding/shima-logo-light.svg" alt="shima by Patrick" width="420">
  </picture>
</p>

<p align="center">
  <strong>島 · "island"</strong>
</p>

A personal, free "Dynamic Island" for the MacBook notch (macOS, Apple Silicon). It shows Claude Code session state, Spotify now-playing and a file shelf in the dead space around the notch. It is a small, local, hackable POC, not a product.

**Status:** M0 (the island shell) is built. The idle island is flush with the notch and invisible. Hover it and a 360x165 black island springs out with concave corners; leave and it collapses. It has no content yet beyond a placeholder (Spotify is M1, Claude sessions M2). `shimactl` is still a stub. Scope and architecture: [docs/2026-11-20-notch-design.md](docs/2026-11-20-notch-design.md). UI target: [mockup/index.html](mockup/index.html).

## Requirements
- macOS 14+, Apple Silicon
- Swift (built with 6.4.2) and either the Command Line Tools or Xcode. **Xcode is not required** and there is no `.xcodeproj`.

## Build and run
```sh
swift build            # debug build
swift test             # unit tests (ShimaCore)
scripts/bundle.sh      # release build -> dist/Shima.app (Info.plist, LSUIElement, ad-hoc codesign)
scripts/run.sh         # bundle + launch
```
The island lives on the built-in display only. It is invisible when idle: on a notched Mac it sits exactly over the notch, and on a built-in display without a notch it is an invisible 200x32 hover zone at top centre. Quit from the menu-bar capsule icon (`Quit shima`, Cmd-Q), or run `pkill -x Shima`. If your menu bar is full, macOS hides the capsule icon (it needs about 38 pt next to the notch); free a slot or use `pkill`. Set `SHIMA_DEBUG=1` (for example `SHIMA_DEBUG=1 scripts/run.sh`) to tint the idle pill red and outline the panel.

Check scripts (run with the app running): `scripts/verify-alignment.sh` (panel vs notch), `scripts/verify-focus.sh` (focus never stolen), `scripts/verify-idle.sh` (60 s idle CPU and memory), `scripts/watch-hover.sh` (live hover and frame log).

## Layout
| Path | What |
|---|---|
| `Sources/ShimaCore` | Library: geometry, display selection, island layout and path, hover state machine; event bus and Unix-socket server next |
| `Sources/Shima` | The accessory app: SwiftUI in a borderless, non-activating `NSPanel` |
| `Sources/shimactl` | CLI the Claude Code hooks will call (`shimactl event <name>`, always exits 0) |
| `Tests/ShimaCoreTests` | Swift Testing tests |
| `scripts/` | `bundle.sh`, `run.sh`, and the `verify-*` / `watch-hover` check scripts |
