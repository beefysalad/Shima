# shima

A personal, free "Dynamic Island" for the MacBook notch (macOS, Apple Silicon). It shows Claude Code session state, Spotify now-playing and a file shelf in the dead space around the notch. It is a small, local, hackable POC, not a product.

**Status:** scaffold only. The app shows a static black pill over the notch; `shimactl` is a stub. Scope and architecture: [docs/2026-11-20-notch-design.md](docs/2026-11-20-notch-design.md). UI target: [mockup/index.html](mockup/index.html).

## Requirements
- macOS 14+, Apple Silicon
- Swift 6.1 and the Command Line Tools. **Xcode is not required** and there is no `.xcodeproj`.

## Build and run
```sh
swift build            # debug build
swift test             # unit tests (ShimaCore)
scripts/bundle.sh      # release build -> dist/Shima.app (Info.plist, LSUIElement, ad-hoc codesign)
scripts/run.sh         # bundle + launch
```
The pill appears over the notch on the built-in display (a centred 200x32 pill on displays without a notch). Quit from the menu-bar capsule icon, or click the pill and press Esc.

## Layout
| Path | What |
|---|---|
| `Sources/ShimaCore` | Library: geometry now; state, event bus and Unix-socket server next |
| `Sources/Shima` | The accessory app: SwiftUI in a borderless, non-activating `NSPanel` |
| `Sources/shimactl` | CLI the Claude Code hooks will call (`shimactl event <name>`, always exits 0) |
| `Tests/ShimaCoreTests` | Swift Testing tests |
| `scripts/` | `bundle.sh`, `run.sh` |
