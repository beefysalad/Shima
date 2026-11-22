<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/branding/shima-logo.svg">
    <img src="assets/branding/shima-logo-light.svg" alt="shima by Patrick" width="420">
  </picture>
</p>

<p align="center">
  <strong>島 · "island"</strong>
</p>

A personal, free "Dynamic Island" for the MacBook notch (macOS, Apple Silicon). It shows Spotify now-playing today and is meant to show Claude Code session state and a file shelf next. It is a small, local, hackable POC, not a product.

**Status**
- **M0, the island shell:** the idle island is flush with the notch and invisible. Hover it and a 400x200 black island springs out with concave corners; leave and it collapses. Built-in display only.
- **M1, Spotify:** while music plays, two small wings grow beside the notch (album art on the left, bouncing green bars on the right). Hover to open the island: artwork, title, artist, a progress bar, and previous, play/pause and next. It is event-driven (no polling), never launches Spotify, and needs the macOS Automation permission for Spotify.
- **Settings window:** a native sidebar with General, Music, Updates and About pages, grouped controls, and light and dark appearances. Includes Launch at login, Quit, Spotify status with a shortcut to the Automation pane, the equalizer mode (animated, only when open, or off), and version and signing info. Open it by launching Shima again (Spotlight or Finder), from the gear on the open island, or from "Settings…" in the status menu. None of these depend on the menu-bar icon having room.
- **Next:** M2, Claude Code session state. `shimactl` is still a stub. Still open from M0: external-monitor and clamshell checks.

Website and download: [beefysalad.github.io/Shima](https://beefysalad.github.io/Shima/).

Scope and architecture: [docs/2026-11-20-notch-design.md](docs/2026-11-20-notch-design.md). UI target: [mockup/index.html](mockup/index.html). Acceptance records: [M0](docs/superpowers/m0-acceptance.md), [M1](docs/superpowers/m1-acceptance.md), [Settings](docs/superpowers/settings-acceptance.md).

## Requirements
- macOS 14+, Apple Silicon
- Swift (built with 6.4.2) and either the Command Line Tools or Xcode. **Xcode is not required** and there is no `.xcodeproj`.

## Build and run
```sh
swift build            # debug build
swift test             # unit tests (ShimaCore)
scripts/bundle.sh      # release build -> dist/Shima.app (Info.plist, icon, LSUIElement, codesign)
scripts/run.sh         # bundle + launch (stops only this checkout's dist instance)
scripts/install.sh     # build and install /Applications/Shima.app (--open to launch)
scripts/package.sh     # build dist/Shima-<version>.dmg and .zip (--release: ad-hoc only, refuses SHIMA_SIGN_ID)
```
The island lives on the built-in display only. It is invisible when idle: on a notched Mac it sits exactly over the notch, and on a built-in display without a notch it is an invisible 200x32 hover zone at top centre. Quit from Settings or the menu-bar capsule icon (`Quit shima`, Cmd-Q), or run `pkill -x Shima`. If your menu bar is full, macOS hides the capsule icon (it needs about 38 pt next to the notch): use the Settings window instead. Set `SHIMA_DEBUG=1` (for example `SHIMA_DEBUG=1 scripts/run.sh`) to tint the idle pill red and outline the panel.

**Install.** `SHIMA_SIGN_ID='Apple Development: you@example.com (CERTID)' scripts/install.sh --open` builds, quits a running Shima, replaces `/Applications/Shima.app` and verifies the signature, so you do not have to build each time. `scripts/package.sh` builds the same bundle and writes `dist/Shima-<version>.dmg` (drag-to-Applications) and `dist/Shima-<version>.zip` instead; `scripts/package.sh --release` is the public-release path and builds ad-hoc only. The build is signed with a development certificate, not notarized: on another Mac, right-click Open once, or run `xattr -dr com.apple.quarantine /Applications/Shima.app`. Launch at login and the Spotify Automation grant need the app in `/Applications` signed with the same identity every time (the install script refuses an ad-hoc rebuild over a certificate-signed install). A development certificate expires after a year; Automation must be granted again then.

**Spotify.** Run `scripts/run.sh` with `SHIMA_SIGN_ID` set (real mode refuses to run ad-hoc). The first Apple Event triggers the macOS Automation prompt; if you deny it, the open island says so and Settings has a button to the right System Settings pane. For tests without touching your Spotify, use fake mode: `SHIMA_FAKE_SPOTIFY=playing scripts/run.sh`, then drive it with `swift scripts/drive.swift "fake next; fake paused"` (see `scripts/drive.swift` for the commands).

**Check scripts** (run with the app running; they drive the pointer and keys with synthetic events): `scripts/verify-alignment.sh [--live|--expanded|--menus]` (panel vs notch), `verify-focus.sh [--clicks]` (focus never stolen), `verify-live-hover.sh`, `verify-idle.sh [--playing]` (60 s idle CPU and memory), `verify-settings.sh` (Settings window, entry points, equalizer modes), `verify-view-layout.sh` (offscreen pixel check of the views), and `watch-hover.sh` (live hover and frame log).

## Updates

Open Settings → Updates → **Check for updates**. On a downloaded, ad-hoc-signed copy in `/Applications/Shima.app`, a newer release offers **Update and restart**. Shima fetches the ZIP and `SHA256SUMS` from its GitHub release over HTTPS, verifies the checksum, archive paths, bundle identity, version and code signature, then quits, replaces the app and restarts. A failed replacement or launch restores the previous bundle; successful updates keep `Previous.app` in the hidden `.shima-update-<UUID>` folder beside Shima for recovery.

Checks run only when you click. There is no automatic update polling. Source builds, certificate-signed installs and unwritable Applications folders show a release link instead. Keep using the same signing identity with `scripts/install.sh` for certificate-signed local builds. The public releases remain ad-hoc signed and not notarized; updating inside Shima does not guarantee Spotify permission will persist. Checksums detect corrupted downloads; they do not provide an independent publisher signature.

The first updater-capable release needs a one-time manual install. Later releases must include the ZIP, updater helper and `SHA256SUMS`; `scripts/package.sh` now produces all required files. `scripts/verify-updater.sh` checks the GUI states, archive verification, helper replacement and launch-failure rollback using fixtures under `.build`, without replacing the installed app.

## Roadmap

- **Spotify Up next:** show the next few tracks beside the player. Spotify's local scripting interface does not expose the queue; this needs an optional Spotify sign-in through the Web API. Keep the current player without a queue until that integration is ready.
- **Release signing:** preserve Spotify Automation permission across public updates, and add Developer ID signing plus notarization for the normal macOS first-launch experience.
- **Claude Code sessions:** show running sessions, requests for attention and completion through `shimactl` hooks.
- **File shelf:** temporarily park files in the island and drag them elsewhere.

## Layout
| Path | What |
|---|---|
| `Sources/ShimaCore` | Library: geometry, display selection, island layout and path, hover state machine, Spotify model, reducer and request gate, artwork request gate, settings model and store; event bus and Unix-socket server next |
| `Sources/Shima` | The accessory app: SwiftUI in a borderless, non-activating `NSPanel`, the wings and open-island views, the Settings window, Apple Event glue |
| `Sources/shimactl` | CLI the Claude Code hooks will call (`shimactl event <name>`, always exits 0) |
| `Tests/ShimaCoreTests` | Swift Testing tests |
| `scripts/` | `bundle.sh`, `run.sh`, `install.sh`, `package.sh`, the `verify-*` / `watch-hover` checks and the `drive` / `shima-windows` / `with-log` helpers |
| `docs/` | Design, plus `superpowers/` specs, plans, spike notes and acceptance records for each milestone |
| `assets/branding/` | Logo and icon sources (`generate.swift`, `export.sh`) and exports |
