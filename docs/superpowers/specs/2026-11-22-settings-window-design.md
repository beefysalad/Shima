# shima: Settings window (design)

Date 2026-11-22. Status: approved by the user in conversation ("Yes go", with the recommendations below). Small milestone between M1 and M2. Parent design: `docs/2026-11-20-notch-design.md`.

## Intent
Quit, Launch at login and Spotify permission help must not depend on the menu-bar capsule having room. On this Mac the capsule is hidden by macOS whenever the menu bar is full (M0 finding, seen again after M1), which also made Launch at login impossible to toggle from the UI. A regular window gives shima a stable place for settings.

## Goals
- A normal window ("shima Settings") that can always be opened without the menu bar.
- v1 contents: Launch at login toggle; Quit shima button; Spotify status (running or not, Automation permission granted or denied) with a button that opens System Settings at Privacy & Security > Automation; Equalizer mode; app version and the signing certificate expiry date.
- Everything testable lives in `ShimaCore` with Swift Testing tests; the window is SwiftUI in `Shima`.

## Non-goals
- No theme, size or per-display options, nothing for Claude sessions or automations yet (M2 and later add their own settings).
- No new dependencies, no `.xcodeproj`, SwiftPM only.
- No change to the island's focus behaviour: the island panel still never takes focus. Only an explicit user action that opens the Settings window may activate the app.

## Anti-goals
- A Dock icon or a menu-bar-only entry. The app stays `LSUIElement` (no Dock icon).
- Any timer or polling while idle. The window refreshes its status when it opens and on user actions only.

## Entry points (all three, user choice)
1. **Re-launching Shima** (Spotlight, Finder, `open /Applications/Shima.app`) while it runs: `applicationShouldHandleReopen` opens the window.
2. **A gear button on the open island** (top-right of the expanded island, outside the now-playing column; works with the existing first-mouse hosting view; opens the window and activates the app because the user clicked it).
3. **The status-menu capsule**, when it has room: a new "Settings…" item (Cmd-,), next to the existing items.

## Settings and persistence
- `LaunchAtLogin`: reads `SMAppService.mainApp.status` each time the window appears or after a toggle; logic stays in the existing `LoginItemMenu` / `LoginItem` code (a registration failure is shown inline as "unavailable").
- `Equalizer mode` (enum `EqualizerMode`): `animated` (default; today's behaviour, bars bounce whenever music plays, cost measured in M1 about +5 to +10 points of WindowServer at 20 fps), `whenOpen` (wings show still bars; bars animate only while the island is open), `off` (wings show still bars). Stored in `UserDefaults` suite `local.shima`, key `equalizerMode`, read once at launch and when changed in the window. My call: UserDefaults for UI preferences now, while `~/.config/shima/config.json` stays reserved for automations (M4) as the parent design says.
- `Spotify status`: derived from the existing `AppState`/`SpotifyAvailability` (running, notRunning, permissionDenied); the button opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`.
- `Quit`: `NSApp.terminate`.
- `About`: version from the bundle, certificate expiry read from the code signature at runtime if cheap, otherwise the fixed text "see docs".

## Approaches considered
1. **SwiftUI `Window` in the existing `NSApplication` delegate app** (chosen): an `NSWindow` hosting a SwiftUI view, created lazily by an `NSWindowController` kept by `AppDelegate`; no new process. Cost: an accessory app must call `NSApp.activate` and may need `setActivationPolicy(.regular)` while the window is open to get a normal window and key focus, then return to `.accessory` on close.
2. A separate helper app for settings: rejected, doubles signing and Automation identity.
3. Putting all controls inside the island: rejected, the island is hover-only and tiny.

## Risks and calls
- **Activation policy.** While the window is open the app may appear in the Dock and the Cmd-Tab list; it returns to `.accessory` when the window closes. Acceptable and expected for a settings window.
- **Focus guarantee.** The island's `canBecomeKey == false` panel and `app became active` log stay unchanged for island interactions; opening Settings from the gear is the one intended activation (log it as `settings opened via <entry>`).
- **Idle cost.** No timers; `verify-idle.sh` strict must still pass with the window closed.
- **Equalizer modes** change only `EqualizerNSView.animating` inputs (`animating` is already idempotent); the `whenOpen` rule is: animate only while the island is expanded and playing.

## Acceptance (for the plan)
1. Each entry point opens the same single window (a second open focuses it, never creates two).
2. Launch at login toggles `SMAppService` and its state matches System Settings (verified by status readback and `sfltool` read-only), ends OFF after the test.
3. Quit ends the process.
4. Spotify status shows the right state in fake mode for running, not running and denied, and the System Settings button logs the URL it opens.
5. Equalizer mode persists across a relaunch and changes the wings' behaviour (log `eq animating`/`eq frozen` lines).
6. Closing the window returns the app to `.accessory` (no Dock icon) and the island behaves as before: `verify-focus.sh --clicks`, `verify-live-hover.sh` and strict idle pass.
7. Works with the menu bar full (the capsule hidden): entry points 1 and 2 are enough.
