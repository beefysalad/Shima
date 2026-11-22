# shima Settings window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A normal "shima Settings" window that opens from three places that do not depend on the menu-bar capsule (re-launching Shima, a gear on the open island, and a "Settings…" item in the status menu when it is visible). It holds Launch at login, Quit, Spotify status with a button to System Settings › Privacy & Security › Automation, the equalizer mode (animated, only when open, off; persisted), and the app version with the signing certificate's expiry. There is only one window, closing it returns the app to `.accessory` and gives focus back, and the island keeps its M1 focus and idle behaviour.

**Architecture:** Pure values and the settings logic live in `ShimaCore` with Swift Testing tests: `EqualizerMode` and `EqualizerPolicy` (visible/animating rule), `SettingsStore` over a `PreferenceStorage` protocol (UserDefaults in the app, in memory in tests), `SettingsText` (Spotify row, version, signing text), `SettingsLinks`, `SettingsLayout` (fixed window geometry that scripts click by), `NowPlayingLayout.settingsButton`, and an `@Observable @MainActor SettingsModel` that both the status menu and the window use (one login-item state, one `registrationFailed` flag). `Shima` is glue: `SystemLoginItemService` over the existing `LoginItem`, `SigningInfo` (Security framework, read once), `SettingsView` (SwiftUI, fixed layout), `SettingsWindowController` (one `NSWindow` with an `NSHostingView`, created on first show, cooperative activation, focus handed back on close), the gear overlay in `IslandView`, the reopen handler and the status-menu item in `AppDelegate`, and new fake-mode commands (`denied`, `allowed`, `eq-mode-<mode>`).

**Tech Stack:** Swift 6.4.2 toolchain (language mode 6, `swift-tools-version:6.0`), SwiftPM, AppKit + SwiftUI (macOS 14+), Observation, Security framework (`SecStaticCode`, `SecCertificate`), ServiceManagement (existing), os.Logger, Swift Testing. No third-party packages.

**Spec:** `docs/superpowers/specs/2026-11-22-settings-window-design.md` (approved, binding): Intent, Goals, Non-goals, Anti-goals, Entry points 1-3, Settings and persistence, Risks and calls, Acceptance 1-7. Context only: `docs/2026-11-20-notch-design.md` section 8. M1 facts and methods: `docs/superpowers/m1-acceptance.md`, `docs/superpowers/plans/2026-11-21-m1-spotify-plan.md`.

## Global Constraints

- SwiftPM only, no `.xcodeproj`. `swift build`, `swift test`. Swift Testing only (`import Testing`, `@Suite`, `@Test`, `#expect`); no XCTest. Baseline before Task 1 (HEAD `90ced10`): `swift test 2>&1 | tail -1` starts with `✔ Test run with 225 tests in 16 suites passed`.
- No third-party dependencies. Do not touch `~/.claude/settings.json` or any file outside the repo. Never modify `mockup/index.html`. Do not run `tccutil`. Never run `defaults write` or `defaults delete` on any domain; `defaults read local.shima equalizerMode` (read-only) is allowed. The app itself writes its own `local.shima` preferences, which is the feature.
- The working tree has the user's uncommitted `assets/branding/*` and `scripts/bundle.sh` changes. Never stage, revert or edit them. Every commit uses explicit `git add <paths>`, never `git add -A` or `git add .`.
- Commit messages have **no tool-attribution trailers** (no `Co-Authored-By`, no "Generated with"); a hook enforces this.
- Logic in `ShimaCore` (no `import AppKit`, no `import SwiftUI` there; Foundation, CoreGraphics and Observation are fine) with tests. AppKit/SwiftUI/Security/ServiceManagement glue in `Shima`. `shimactl` untouched.
- **Spotify safety.** Spotify is running on the user's Mac. No step launches, quits or sends anything to Spotify. Every automated run uses fake mode (`SHIMA_FAKE_SPOTIFY=playing|paused`) and the `fake <cmd>` channel of `scripts/drive.swift`. Scripts that launch Shima check the `spotify mode fake` log line and stop their instance if it is missing. Real mode is only ever started by the user.
- **Processes.** Never `pkill -x Shima` (it kills Codex's and the installed instance too). Check `pgrep -lx Shima` and kill by pid, and only pids whose command is under this checkout's `dist/Shima.app/` (or `/Applications/Shima.app/` where a step says so). Task 6 makes `scripts/run.sh` follow this rule.
- **Focus.** The island panel never becomes key or main and never activates the app, including the gear click itself (`settings gear clicked active=false key=false`). The only activation is showing the Settings window after an explicit user action (reopen, gear, menu item), logged as `settings opened via <entry>`. Closing the window hands activation back to the previously active app and leaves the policy `.accessory`. Tests that open the window restore the frontmost app (`open -b <bundle id>`) if it is not back.
- **Idle rule (M0/M1, unchanged).** No timers, no event monitors, no polling, no display links. The window refreshes on open and on user actions only. Allowed one-shot work: `DispatchQueue.main.async` for a log line. Allowed observers: notifications (they only run when something happens). `scripts/verify-idle.sh` strict must pass with the window closed, after it was opened and closed.
- **Layout lesson (M1).** A hidden SwiftUI view still takes part in layout. Nothing new may enlarge `IslandView`'s root `ZStack`: the gear is an `.overlay` with an explicit island-sized frame; the equalizer's visibility is an `.opacity` on a child with explicit frames. `scripts/verify-view-layout.sh --now-playing` must keep passing (Task 8 updates its expectations, Task 10 adds the gear check).
- **Equalizer identity (M1).** `EqualizerView` stays in the hierarchy (never inside an `if`); modes change only its `animating` input (`EqualizerNSView.animating` is idempotent). A locked screen freezes the equalizer (occlusion): every `eq animating` check first confirms the screen is unlocked.
- **Hands-off budget (user feedback).** Pointer- or keyboard-driven runs are announced first and last at most about 2 minutes each (`verify-settings.sh` about 60-90 s). CPU checks measure Shima's own CPU (robust to background use) and only need the pointer away from the notch. Use `caffeinate -dimsu` around runs.
- **Signing.** Automated runs build ad-hoc from `dist/` (leave `SHIMA_SIGN_ID` unset). The `/Applications` install uses `SHIMA_SIGN_ID='Apple Development: jpatrickzephyr@gmail.com (<cert-id>)' scripts/install.sh`; a keychain prompt is HUMAN (it did not appear last time). Launch at login is toggled only on the signed `/Applications` copy, never on `dist/`.
- Verification methods that work on this Mac: CGEvent pointer and key input (`scripts/drive.swift`), `os.Logger` read with `/usr/bin/log stream` (in zsh `log` is a builtin: always write `/usr/bin/log`), the window list (`scripts/shima-windows.swift`, `CGWindowListCopyWindowInfo`), offscreen `cacheDisplay` renders (`scripts/verify-view-layout.sh`). No Screen Recording permission: no screenshots, and `kCGWindowName` (window titles) is not readable, so windows are identified by owner, pid and layer. In menu tests, hover an item about 150 ms before clicking it.
- Pointer coordinates (global top-left CG points, built-in screen `1470 x 956`, notch `x 646..825`, midX `735.5`): notch centre `N = 735 16`, away `A = 735 400`, gear `GEAR = 889.5 50` (Task 5), island controls as in M1. The status item's x is read from Shima's own log (Task 11). An external display was attached on 2026-11-22 (window list showed screens at x 1470+); the Settings window may open there, so scripts click relative to its measured bounds.
- Settings window click points (content coordinates, top-left, pinned by `SettingsLayoutTests` and copied into `scripts/verify-settings.sh`): Launch at login `28 50`, equalizer Animated `185 108`, Only when open `275 108`, Off `365 108`, Open Automation Settings `135 240`, Quit `370 352`. Content height `380`; a content point `(cx, cy)` is at global `(win.x + cx, win.y + win.h - 380 + cy)`.
- Test counts in "Expected" lines assume plan order. If tasks run in another order, check that the count grew by the task's own number.

## Review Focus

The risks a reviewer must check across tasks. Each line names the owning test or check.

1. **Focus.** Island clicks (controls and the gear click itself) never activate the app; only showing the window does; after close the app is `.accessory`, not active, and the previous app is frontmost again. Checks: `settings gear clicked active=false key=false` (Task 10, `verify-settings.sh` C1), `settings closed policy=accessory restored=<bundle id>` (B1, B2, G8), `scripts/verify-focus.sh --clicks` after close (Task 14).
2. **One window.** Every entry reuses the same `SettingsWindow`; `settings window created` appears once per process; the Shima pid owns exactly one layer-0 window while open and none after close. Checks: `verify-settings.sh` A1, A2, C2, C3, D1 (`created=false`, `settings windows: 1`).
3. **Island layout.** The gear overlay and the per-child equalizer opacity never change the root size: live `245 x 32` black rows `0..<32`, equalizer bounds `(220.5, 9, 16, 14)` live and `(296, 9, 16, 14)` expanded, gear glyph inside its rect only while expanded, no gear pixels collapsed. Check: `scripts/verify-view-layout.sh --now-playing` (Tasks 8, 10).
4. **Equalizer modes.** `animated` keeps M1's collapsed behaviour and now also animates in the open island; `whenOpen` animates only while expanded with a track playing; `off` never animates; `frozen` (fake A/B) and paused always win; the view is never rebuilt (one `eq animating`/`eq frozen` line per transition). Tests: `EqualizerModeTests` (Task 1); runs: Task 8 Step 4, `verify-settings.sh` E1-E5, G3-G6.
5. **Persistence and domain.** In the bundle (`local.shima`) the store uses `UserDefaults.standard` (no "own bundle identifier as suite name" warning); unknown stored values read as `animated` and are never rewritten on read; tests never touch real defaults; runs end with `equalizerMode = animated`. Tests: `SettingsStoreTests`; check: `verify-settings.sh` G7.
6. **Login item.** Menu and window share `SettingsModel` (one `loginRegistrationFailed`); a failed register makes it "unavailable" in both; `dist/` is never registered; the real run ends OFF. Tests: `SettingsModelTests`; checks: Task 13 (`verify-settings.sh --login-item`).
7. **Idle.** No timers or repeating work added; the only new always-on code is a workspace `didDeactivateApplication` observer and SwiftUI `onChange`. Checks: `verify-idle.sh` static check and strict run after open/close (Task 14).
8. **Spotify safety.** No real-mode run in automation; `fake denied`/`fake allowed`/`fake eq-mode-*` exist only in fake mode; the Automation button in tests runs dry (`SHIMA_SETTINGS_DRY_OPEN=1`). Checks: `spotify mode fake` guard in `verify-settings.sh`, Task 7 Step 3, `pgrep -x Spotify` pid unchanged before and after Task 14.
9. **Process hygiene.** No `pkill` anywhere new; `run.sh` and `verify-settings.sh` kill only their own pids. Check: `grep -rn 'pkill' scripts` prints nothing after Task 6.

---

## File Map

| File | Status | Task | Responsibility |
|---|---|---|---|
| `Sources/ShimaCore/EqualizerMode.swift` | create | 1 | `EqualizerMode`, `EqualizerPolicy` |
| `Sources/ShimaCore/AppState.swift` | modify | 1 | `equalizerMode` |
| `Sources/ShimaCore/SettingsStore.swift` | create | 2 | `PreferenceStorage`, `InMemoryPreferenceStorage`, `UserDefaultsPreferenceStorage`, `SettingsStore` |
| `Sources/ShimaCore/SettingsText.swift` | create | 3 | `SpotifyStatusKind`, `SpotifyStatusRow`, `SigningSummary`, `SettingsLinks`, `SettingsText` |
| `Sources/ShimaCore/SettingsLayout.swift` | create | 3 | fixed Settings window geometry and click points |
| `Sources/ShimaCore/SettingsModel.swift` | create | 4 | `LoginItemService`, `SettingsEntry`, `LoginItemToggle`, `SettingsModel` |
| `Sources/ShimaCore/NowPlayingLayout.swift` | modify | 5 | `titleWidth`, `titleRect`, `settingsButton`, `settingsButtonCenter` |
| `Tests/ShimaCoreTests/EqualizerModeTests.swift` | create | 1 | tests |
| `Tests/ShimaCoreTests/SettingsStoreTests.swift` | create | 2 | tests |
| `Tests/ShimaCoreTests/SettingsTextTests.swift` | create | 3 | `SettingsTextTests`, `SettingsLayoutTests` |
| `Tests/ShimaCoreTests/FakeLoginItemService.swift` | create | 4 | test double |
| `Tests/ShimaCoreTests/SettingsModelTests.swift` | create | 4 | tests |
| `Tests/ShimaCoreTests/NowPlayingLayoutTests.swift` | modify | 5 | gear tests |
| `scripts/run.sh` | modify | 6 | stop only this checkout's dist Shima, by pid |
| `scripts/drive.swift` | modify | 6 | `key esc|tab|space|return|cmd-w|cmd-comma` with a 20 ms down/up gap |
| `scripts/shima-windows.swift` | modify | 6 | `--settings [pid]`: Shima's layer-0 windows |
| `Sources/Shima/Log.swift` | modify | 7 | category `settings` |
| `Sources/Shima/LoginItem.swift` | modify | 7 | `SystemLoginItemService` |
| `Sources/Shima/SigningInfo.swift` | create | 7 | reads the app's own signature and certificate expiry |
| `Sources/Shima/SpotifyService.swift` | modify | 7 | fake `denied`, `allowed`, `eq-mode-<mode>` |
| `Sources/Shima/AppDelegate.swift` | modify | 7, 9, 10, 11 | `SettingsModel`, menu via the model, reopen, gear and menu entries, dry-run URL open |
| `Sources/Shima/WingsView.swift` | modify | 8 | `EqualizerPolicy` inputs, per-child opacity |
| `scripts/view-layout-check.swift` | modify | 8, 10 | equalizer visible in the open island, mini artwork hidden, gear glyph, `--now-playing` by default |
| `Sources/Shima/SettingsView.swift` | create | 9 | SwiftUI window content at `SettingsLayout` positions |
| `Sources/Shima/SettingsWindowController.swift` | create | 9 | `SettingsWindow` (Cmd-W), single window, activation, focus hand-back |
| `Sources/Shima/IslandView.swift` | modify | 10 | `onSettings`, `SettingsGear` overlay |
| `Sources/Shima/NowPlayingView.swift` | modify | 10 | title frame uses `titleRect` |
| `Sources/Shima/IslandPanelController.swift` | modify | 10 | `onSettings`, `settings gear clicked` log |
| `scripts/verify-settings.sh` | create | 12 | hands-off fake-mode checks; `--login-item` on the installed app |
| `docs/superpowers/settings-acceptance.md` | create | 9, 14 | decisions (activation) and the acceptance record |

## Who can do what in parallel

- **PURE, parallel-safe (second engineer, Codex):** Tasks 1-5 touch only `Sources/ShimaCore` and `Tests/ShimaCoreTests`. Work in a worktree on its own branch: `git worktree add .worktrees/settings-pure -b settings-pure main` (`.worktrees/` is already excluded in `.git/info/exclude`), then `cd .worktrees/settings-pure`. Internal order: 1, 2, 3 (any order), then 4 (needs 1-3); 5 is independent. Codex runs only `swift build` and `swift test`: it never launches Shima, never runs `scripts/*.sh`, never touches `Sources/Shima`, `scripts/`, `docs/` or the user's branding files, and commits each task with the given command. When done it reports the five commit hashes and the last `swift test` line (`✔ Test run with 270 tests in 21 suites passed`).
- **Controller, in parallel with Codex:** Task 6 (SCRIPT) on `main` in the main checkout; it touches only `scripts/run.sh`, `scripts/drive.swift`, `scripts/shima-windows.swift`, so it merges cleanly.
- **Merge point:** after reviewing Tasks 1-5, the controller runs `git merge --no-ff settings-pure -m "Merge settings-pure: equalizer mode, settings store, text, layout and model"` on `main`, then `swift test 2>&1 | tail -1` (expected `✔ Test run with 270 tests in 21 suites passed`), then `git worktree remove .worktrees/settings-pure`.
- **GLUE, SCRIPT, HUMAN, sequential (controller):** Tasks 7-14 share `AppDelegate.swift`, `IslandView.swift`, `IslandPanelController.swift` and the running app (one island on one notch: two GUI runs at once would fight over the pointer and the log). Run them one at a time after the merge. HUMAN parts: Task 13 (keychain prompt if any, System Settings glances, the real Automation button), Task 14 (announced hands-off batches, final reopen of the installed app).

---

### Task 1: EqualizerMode, EqualizerPolicy and AppState.equalizerMode (PURE, parallel-safe)

**Files:**
- Create: `Sources/ShimaCore/EqualizerMode.swift`
- Modify: `Sources/ShimaCore/AppState.swift`
- Test: `Tests/ShimaCoreTests/EqualizerModeTests.swift`

**Interfaces:**
- Produces:
```swift
public enum EqualizerMode: String, CaseIterable, Equatable, Sendable {
    case animated, whenOpen, off
    public static let `default`: EqualizerMode           // .animated
    public init(stored: String?)                           // nil or unknown -> .animated
    public var title: String                               // "Animated", "Only when open", "Off"
}
public enum EqualizerPolicy {
    public static func isVisible(island: IslandMode, live: Bool, content: NowPlayingContent) -> Bool
    public static func isAnimating(_ mode: EqualizerMode, island: IslandMode, live: Bool,
                                   content: NowPlayingContent, playing: Bool, frozen: Bool) -> Bool
}
// AppState
public var equalizerMode: EqualizerMode = .animated
```
- Rule (plan note 1): the equalizer sits right of the notch. Collapsed it is visible when `live`; expanded it is visible when `content == .track` (same spot, in the open island's top strip). It animates only when visible, playing and not frozen, and then: `animated` always, `whenOpen` only when `island == .expanded`, `off` never.

- [ ] **Step 1: Write the failing tests**

`Tests/ShimaCoreTests/EqualizerModeTests.swift`:
```swift
import Testing
@testable import ShimaCore

@Suite struct EqualizerModeTests {
    typealias P = EqualizerPolicy

    @Test func storedValuesRoundTrip() {
        for mode in EqualizerMode.allCases { #expect(EqualizerMode(stored: mode.rawValue) == mode) }
        #expect(EqualizerMode.allCases.map(\.rawValue) == ["animated", "whenOpen", "off"])
    }
    @Test func unknownOrMissingFallsBackToAnimated() {
        #expect(EqualizerMode(stored: nil) == .animated)
        #expect(EqualizerMode(stored: "") == .animated)
        #expect(EqualizerMode(stored: "Off") == .animated)
        #expect(EqualizerMode.default == .animated)
    }
    @Test func titles() {
        #expect(EqualizerMode.allCases.map(\.title) == ["Animated", "Only when open", "Off"])
    }
    @Test func visibleCollapsedOnlyWhenLive() {
        #expect(P.isVisible(island: .collapsed, live: true, content: .track))
        #expect(!P.isVisible(island: .collapsed, live: false, content: .track))
    }
    @Test func visibleExpandedOnlyWithTrack() {
        #expect(P.isVisible(island: .expanded, live: false, content: .track))
        for content in [NowPlayingContent.notRunning, .permissionDenied, .nothingPlaying] {
            #expect(!P.isVisible(island: .expanded, live: true, content: content))
        }
    }
    @Test func animatedMatchesM1WhenCollapsed() {
        #expect(P.isAnimating(.animated, island: .collapsed, live: true, content: .track, playing: true, frozen: false))
        #expect(!P.isAnimating(.animated, island: .collapsed, live: false, content: .track, playing: true, frozen: false))
    }
    @Test func animatedAlsoAnimatesInTheOpenIsland() {
        #expect(P.isAnimating(.animated, island: .expanded, live: true, content: .track, playing: true, frozen: false))
    }
    @Test func whenOpenAnimatesOnlyExpanded() {
        #expect(!P.isAnimating(.whenOpen, island: .collapsed, live: true, content: .track, playing: true, frozen: false))
        #expect(P.isAnimating(.whenOpen, island: .expanded, live: true, content: .track, playing: true, frozen: false))
        #expect(!P.isAnimating(.whenOpen, island: .expanded, live: true, content: .permissionDenied, playing: true, frozen: false))
    }
    @Test func offNeverAnimates() {
        for island in [IslandMode.collapsed, .expanded] {
            for live in [false, true] {
                #expect(!P.isAnimating(.off, island: island, live: live, content: .track, playing: true, frozen: false))
            }
        }
    }
    @Test func pausedOrFrozenNeverAnimates() {
        for mode in EqualizerMode.allCases {
            for island in [IslandMode.collapsed, .expanded] {
                #expect(!P.isAnimating(mode, island: island, live: true, content: .track, playing: false, frozen: false))
                #expect(!P.isAnimating(mode, island: island, live: true, content: .track, playing: true, frozen: true))
            }
        }
    }
    @Test @MainActor func appStateDefaultsToAnimated() {
        #expect(AppState().equalizerMode == .animated)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter EqualizerModeTests 2>&1 | grep -m1 error:`
Expected: `error: cannot find 'EqualizerMode' in scope` (or `EqualizerPolicy`).

- [ ] **Step 3: Implement**

`Sources/ShimaCore/EqualizerMode.swift`:
```swift
/// How the equalizer behaves (Settings window). Stored by raw value in `local.shima` / `equalizerMode`.
public enum EqualizerMode: String, CaseIterable, Equatable, Sendable {
    case animated, whenOpen, off

    public static let `default`: EqualizerMode = .animated

    /// Reads a stored raw value; nil or an unknown value means the default.
    public init(stored: String?) {
        self = stored.flatMap(EqualizerMode.init(rawValue:)) ?? .default
    }

    public var title: String {
        switch self {
        case .animated: "Animated"
        case .whenOpen: "Only when open"
        case .off: "Off"
        }
    }
}

/// The equalizer sits right of the notch: in the live wing while collapsed, and at the same spot in the
/// open island's top strip while a track is shown. Modes change only whether its bars animate.
public enum EqualizerPolicy {
    public static func isVisible(island: IslandMode, live: Bool, content: NowPlayingContent) -> Bool {
        switch island {
        case .collapsed: live
        case .expanded: content == .track
        }
    }

    public static func isAnimating(_ mode: EqualizerMode, island: IslandMode, live: Bool,
                                   content: NowPlayingContent, playing: Bool, frozen: Bool) -> Bool {
        guard playing, !frozen, isVisible(island: island, live: live, content: content) else { return false }
        switch mode {
        case .animated: return true
        case .whenOpen: return island == .expanded
        case .off: return false
        }
    }
}
```
In `Sources/ShimaCore/AppState.swift`, after `public var spotifyAvailability: SpotifyAvailability = .notRunning`, add:
```swift
    /// Applied by `SettingsModel` at launch and when changed in the Settings window.
    public var equalizerMode: EqualizerMode = .animated
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test 2>&1 | tail -1`
Expected: starts with `✔ Test run with 236 tests in 17 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShimaCore/EqualizerMode.swift Sources/ShimaCore/AppState.swift Tests/ShimaCoreTests/EqualizerModeTests.swift
git commit -m "Add EqualizerMode and the equalizer visibility and animation rule"
```

---

### Task 2: SettingsStore over a PreferenceStorage protocol (PURE, parallel-safe)

**Files:**
- Create: `Sources/ShimaCore/SettingsStore.swift`
- Test: `Tests/ShimaCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `EqualizerMode` (Task 1).
- Produces:
```swift
@MainActor public protocol PreferenceStorage: AnyObject {
    func string(forKey key: String) -> String?
    func setString(_ value: String, forKey key: String)
}
@MainActor public final class InMemoryPreferenceStorage: PreferenceStorage {
    public private(set) var values: [String: String]
    public private(set) var writes: Int
    public init(_ values: [String: String] = [:])
}
@MainActor public final class UserDefaultsPreferenceStorage: PreferenceStorage {
    public init(defaults: UserDefaults)
    public static func forShima(bundleIdentifier: String?) -> UserDefaultsPreferenceStorage
}
@MainActor public final class SettingsStore {
    public static let suiteName = "local.shima"
    public static let equalizerModeKey = "equalizerMode"
    public init(storage: PreferenceStorage)
    public static func usesStandardDefaults(bundleIdentifier: String?) -> Bool   // true only for "local.shima"
    public var equalizerMode: EqualizerMode { get }                              // reads storage each call
    public func setEqualizerMode(_ mode: EqualizerMode)                          // writes only when the raw value differs
}
```
- Why `forShima`: inside `Shima.app` the bundle id is `local.shima`, so `UserDefaults.standard` already is the design's `local.shima` domain (`~/Library/Preferences/local.shima.plist`); `UserDefaults(suiteName: "local.shima")` from inside that bundle only logs "Using your own bundle identifier as an NSUserDefaults suite name does not make sense". Unbundled (`swift run`) it uses the suite, which is the same plist. Plan note 3. Unit tests use only `InMemoryPreferenceStorage` and never touch real defaults.

- [ ] **Step 1: Write the failing tests**

`Tests/ShimaCoreTests/SettingsStoreTests.swift`:
```swift
import Testing
@testable import ShimaCore

@Suite @MainActor struct SettingsStoreTests {
    @Test func defaultsToAnimatedWhenEmpty() {
        #expect(SettingsStore(storage: InMemoryPreferenceStorage()).equalizerMode == .animated)
    }
    @Test func readsStoredMode() {
        #expect(SettingsStore(storage: InMemoryPreferenceStorage(["equalizerMode": "whenOpen"])).equalizerMode == .whenOpen)
    }
    @Test func setWritesRawValueUnderTheKey() {
        let storage = InMemoryPreferenceStorage()
        let store = SettingsStore(storage: storage)
        store.setEqualizerMode(.off)
        #expect(storage.values == ["equalizerMode": "off"] && storage.writes == 1 && store.equalizerMode == .off)
    }
    @Test func settingTheSameModeDoesNotWrite() {
        let storage = InMemoryPreferenceStorage(["equalizerMode": "off"])
        SettingsStore(storage: storage).setEqualizerMode(.off)
        #expect(storage.writes == 0)
    }
    @Test func unknownStoredValueReadsAsDefaultAndIsReplacedOnlyOnSet() {
        let storage = InMemoryPreferenceStorage(["equalizerMode": "loud"])
        let store = SettingsStore(storage: storage)
        #expect(store.equalizerMode == .animated && storage.writes == 0)
        store.setEqualizerMode(.animated)
        #expect(storage.values["equalizerMode"] == "animated" && storage.writes == 1)
    }
    @Test func onlyTheShimaBundleUsesStandardDefaults() {
        #expect(SettingsStore.suiteName == "local.shima" && SettingsStore.equalizerModeKey == "equalizerMode")
        #expect(SettingsStore.usesStandardDefaults(bundleIdentifier: "local.shima"))
        #expect(!SettingsStore.usesStandardDefaults(bundleIdentifier: nil))
        #expect(!SettingsStore.usesStandardDefaults(bundleIdentifier: "com.apple.dt.xctest.tool"))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter SettingsStoreTests 2>&1 | grep -m1 error:`
Expected: `error: cannot find 'SettingsStore' in scope` (or `InMemoryPreferenceStorage`).

- [ ] **Step 3: Implement**

`Sources/ShimaCore/SettingsStore.swift`:
```swift
import Foundation

/// String key-value storage behind the settings: UserDefaults in the app, in memory in tests.
@MainActor public protocol PreferenceStorage: AnyObject {
    func string(forKey key: String) -> String?
    func setString(_ value: String, forKey key: String)
}

@MainActor public final class InMemoryPreferenceStorage: PreferenceStorage {
    public private(set) var values: [String: String]
    public private(set) var writes = 0

    public init(_ values: [String: String] = [:]) { self.values = values }

    public func string(forKey key: String) -> String? { values[key] }

    public func setString(_ value: String, forKey key: String) {
        values[key] = value
        writes += 1
    }
}

@MainActor public final class UserDefaultsPreferenceStorage: PreferenceStorage {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    /// Inside Shima.app (bundle id `local.shima`) the standard defaults already are the `local.shima`
    /// domain, and a suite named like the own bundle id only logs a warning. Elsewhere use the suite.
    public static func forShima(bundleIdentifier: String?) -> UserDefaultsPreferenceStorage {
        if SettingsStore.usesStandardDefaults(bundleIdentifier: bundleIdentifier) {
            return UserDefaultsPreferenceStorage(defaults: .standard)
        }
        return UserDefaultsPreferenceStorage(defaults: UserDefaults(suiteName: SettingsStore.suiteName) ?? .standard)
    }

    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }

    public func setString(_ value: String, forKey key: String) { defaults.set(value, forKey: key) }
}

/// UI preferences (design: UserDefaults now; `~/.config/shima/config.json` stays reserved for M4 automations).
@MainActor public final class SettingsStore {
    public static let suiteName = "local.shima"
    public static let equalizerModeKey = "equalizerMode"

    private let storage: PreferenceStorage

    public init(storage: PreferenceStorage) { self.storage = storage }

    public static func usesStandardDefaults(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == suiteName
    }

    public var equalizerMode: EqualizerMode {
        EqualizerMode(stored: storage.string(forKey: Self.equalizerModeKey))
    }

    public func setEqualizerMode(_ mode: EqualizerMode) {
        guard storage.string(forKey: Self.equalizerModeKey) != mode.rawValue else { return }
        storage.setString(mode.rawValue, forKey: Self.equalizerModeKey)
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test 2>&1 | tail -1`
Expected: starts with `✔ Test run with 242 tests in 18 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShimaCore/SettingsStore.swift Tests/ShimaCoreTests/SettingsStoreTests.swift
git commit -m "Add SettingsStore with UserDefaults and in-memory storage"
```

---

### Task 3: SettingsText, SettingsLinks and SettingsLayout (PURE, parallel-safe)

**Files:**
- Create: `Sources/ShimaCore/SettingsText.swift`, `Sources/ShimaCore/SettingsLayout.swift`
- Test: `Tests/ShimaCoreTests/SettingsTextTests.swift` (two suites)

**Interfaces:**
- Consumes: `SpotifyAvailability` (M1), `EqualizerMode` (Task 1).
- Produces:
```swift
public enum SpotifyStatusKind: String, Equatable, Sendable { case running, notRunning, permissionDenied }
public struct SpotifyStatusRow: Equatable, Sendable {
    public let kind: SpotifyStatusKind
    public let title: String, detail: String, buttonTitle: String
    public let buttonProminent: Bool
}
public enum SigningSummary: Equatable, Sendable {
    case adHoc
    case certificate(commonName: String, notAfter: Date?)
    case unreadable
}
public enum SettingsLinks {
    public static let automation: URL   // x-apple.systempreferences:com.apple.preference.security?Privacy_Automation
}
public enum SettingsText {
    public static let windowTitle = "shima Settings"
    public static let automationButton = "Open Automation Settings…"
    public static let quitButton = "Quit shima"
    public static let expiryWarningDays = 30
    public static func spotifyRow(_ availability: SpotifyAvailability) -> SpotifyStatusRow
    public static func version(short: String?, build: String?) -> String   // "Version 0.0.1 (1)"
    public static func signing(_ summary: SigningSummary, now: Date) -> String
}
public enum SettingsLayout {   // content coordinates, top-left points
    public static let size: CGSize                       // 440 x 380
    public static let generalHeader, spotifyHeader, aboutHeader: CGRect
    public static let launchAtLogin, equalizerLabel: CGRect
    public static func equalizerSegment(_ mode: EqualizerMode) -> CGRect
    public static let spotifyTitle, spotifyDetail, automationButton, version, signing, quitButton: CGRect
    public static var launchAtLoginClick: CGPoint        // the checkbox at the toggle's leading edge
    public static func center(_ rect: CGRect) -> CGPoint
    public static var allRects: [CGRect]
}
```
- Texts (plan note 4): `.running` cannot tell "allowed" from "not asked yet" (M1 marks denial only after a `-1743`), so its detail says exactly that. The signing text shows only the part of the certificate name before `:` ("Apple Development"), never the email. Dates are the UTC day (`yyyy-MM-dd`), matching `openssl x509 -enddate`.

- [ ] **Step 1: Write the failing tests**

`Tests/ShimaCoreTests/SettingsTextTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import ShimaCore

@Suite struct SettingsTextTests {
    func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    let cert = "Apple Development: someone@example.com (TEAMID1234)"

    @Test func spotifyRunning() {
        #expect(SettingsText.spotifyRow(.running) == SpotifyStatusRow(
            kind: .running, title: "Spotify is running", detail: "Automation: allowed, or not asked yet.",
            buttonTitle: "Open Automation Settings…", buttonProminent: false))
    }
    @Test func spotifyNotRunning() {
        let row = SettingsText.spotifyRow(.notRunning)
        #expect(row.kind == .notRunning && row.title == "Spotify is not running" && !row.buttonProminent)
        #expect(row.detail == "shima checks the Automation permission when Spotify runs.")
    }
    @Test func spotifyDeniedIsProminent() {
        let row = SettingsText.spotifyRow(.permissionDenied)
        #expect(row.kind == .permissionDenied && row.title == "shima can't control Spotify" && row.buttonProminent)
        #expect(row.detail == "Allow it in System Settings › Privacy & Security › Automation › Shima.")
        #expect(row.buttonTitle == SettingsText.automationButton)
    }
    @Test func automationURL() {
        #expect(SettingsLinks.automation.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }
    @Test func versionText() {
        #expect(SettingsText.version(short: "0.0.1", build: "1") == "Version 0.0.1 (1)")
        #expect(SettingsText.version(short: "0.0.1", build: nil) == "Version 0.0.1")
        #expect(SettingsText.version(short: nil, build: "1") == "Version unknown")
        #expect(SettingsText.version(short: "", build: nil) == "Version unknown")
    }
    @Test func adHoc() {
        #expect(SettingsText.signing(.adHoc, now: utc("2026-11-22T00:00:00Z")) == "Signed ad hoc (no certificate)")
    }
    @Test func certificateShowsKindAndUTCDay() {
        #expect(SettingsText.signing(.certificate(commonName: cert, notAfter: utc("2027-03-26T08:30:00Z")), now: utc("2026-11-22T00:00:00Z"))
                == "Apple Development certificate expires 2027-03-26")
    }
    @Test func lateUTCTimeStaysOnItsDay() {
        #expect(SettingsText.signing(.certificate(commonName: cert, notAfter: utc("2027-03-26T23:59:00Z")), now: utc("2026-11-22T00:00:00Z"))
                == "Apple Development certificate expires 2027-03-26")
    }
    @Test func expiringSoonShowsDays() {
        #expect(SettingsText.signing(.certificate(commonName: cert, notAfter: utc("2027-03-26T08:30:00Z")), now: utc("2027-03-10T08:30:00Z"))
                == "Apple Development certificate expires 2027-03-26 (in 16 days)")
    }
    @Test func expired() {
        #expect(SettingsText.signing(.certificate(commonName: cert, notAfter: utc("2027-03-26T08:30:00Z")), now: utc("2027-03-27T00:00:00Z"))
                == "Apple Development certificate expired 2027-03-26; Automation must be granted again")
    }
    @Test func unknownSaysSeeDocs() {
        let now = utc("2026-11-22T00:00:00Z")
        #expect(SettingsText.signing(.unreadable, now: now) == "Signing certificate: see docs")
        #expect(SettingsText.signing(.certificate(commonName: cert, notAfter: nil), now: now) == "Signing certificate: see docs")
    }
}

@Suite struct SettingsLayoutTests {
    /// scripts/verify-settings.sh copies these numbers; change both together.
    @Test func sizeAndClickPointsArePinned() {
        #expect(SettingsLayout.size == CGSize(width: 440, height: 380))
        #expect(SettingsLayout.launchAtLoginClick == CGPoint(x: 28, y: 50))
        #expect(EqualizerMode.allCases.map { SettingsLayout.center(SettingsLayout.equalizerSegment($0)) }
                == [CGPoint(x: 185, y: 108), CGPoint(x: 275, y: 108), CGPoint(x: 365, y: 108)])
        #expect(SettingsLayout.center(SettingsLayout.automationButton) == CGPoint(x: 135, y: 240))
        #expect(SettingsLayout.center(SettingsLayout.quitButton) == CGPoint(x: 370, y: 352))
    }
    @Test func controlsFitAndDoNotOverlap() {
        let bounds = CGRect(origin: .zero, size: SettingsLayout.size)
        let rects = SettingsLayout.allRects
        #expect(rects.count == 14)
        for r in rects { #expect(bounds.contains(r)) }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || overlap.width * overlap.height == 0, "rects \(i) and \(j) overlap")
            }
        }
    }
    @Test func segmentsAreEqualAndAdjacent() {
        let s = EqualizerMode.allCases.map(SettingsLayout.equalizerSegment)
        #expect(s.allSatisfy { $0.size == CGSize(width: 90, height: 28) })
        #expect(s[0].maxX == s[1].minX && s[1].maxX == s[2].minX && s[0].minX > SettingsLayout.equalizerLabel.maxX)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter 'SettingsTextTests|SettingsLayoutTests' 2>&1 | grep -m1 error:`
Expected: `error: cannot find 'SettingsText' in scope` (or `SettingsLayout`, `SettingsLinks`).

- [ ] **Step 3: Implement**

`Sources/ShimaCore/SettingsText.swift`:
```swift
import Foundation

public enum SpotifyStatusKind: String, Equatable, Sendable {
    case running, notRunning, permissionDenied
}

public struct SpotifyStatusRow: Equatable, Sendable {
    public let kind: SpotifyStatusKind
    public let title: String
    public let detail: String
    public let buttonTitle: String
    public let buttonProminent: Bool
}

public enum SigningSummary: Equatable, Sendable {
    case adHoc
    case certificate(commonName: String, notAfter: Date?)
    case unreadable
}

public enum SettingsLinks {
    public static let automation = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
}

public enum SettingsText {
    public static let windowTitle = "shima Settings"
    public static let automationButton = "Open Automation Settings…"
    public static let quitButton = "Quit shima"
    public static let expiryWarningDays = 30

    /// `.running` only means no denial was seen since Spotify launched (M1 marks denial on error -1743).
    public static func spotifyRow(_ availability: SpotifyAvailability) -> SpotifyStatusRow {
        switch availability {
        case .running:
            SpotifyStatusRow(kind: .running, title: "Spotify is running",
                             detail: "Automation: allowed, or not asked yet.",
                             buttonTitle: automationButton, buttonProminent: false)
        case .notRunning:
            SpotifyStatusRow(kind: .notRunning, title: "Spotify is not running",
                             detail: "shima checks the Automation permission when Spotify runs.",
                             buttonTitle: automationButton, buttonProminent: false)
        case .permissionDenied:
            SpotifyStatusRow(kind: .permissionDenied, title: "shima can't control Spotify",
                             detail: "Allow it in System Settings › Privacy & Security › Automation › Shima.",
                             buttonTitle: automationButton, buttonProminent: true)
        }
    }

    public static func version(short: String?, build: String?) -> String {
        guard let short, !short.isEmpty else { return "Version unknown" }
        guard let build, !build.isEmpty else { return "Version \(short)" }
        return "Version \(short) (\(build))"
    }

    public static func signing(_ summary: SigningSummary, now: Date) -> String {
        switch summary {
        case .adHoc:
            return "Signed ad hoc (no certificate)"
        case .unreadable, .certificate(_, .none):
            return "Signing certificate: see docs"
        case let .certificate(name, notAfter?):
            let kind = name.split(separator: ":", maxSplits: 1).first.map(String.init) ?? name
            let day = utcDay(notAfter)
            if notAfter <= now { return "\(kind) certificate expired \(day); Automation must be granted again" }
            let days = Int((notAfter.timeIntervalSince(now) / 86_400).rounded(.down))
            if days < expiryWarningDays { return "\(kind) certificate expires \(day) (in \(days) days)" }
            return "\(kind) certificate expires \(day)"
        }
    }

    static func utcDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
```
`Sources/ShimaCore/SettingsLayout.swift`:
```swift
import CoreGraphics

/// Settings window content geometry, top-left points. Fixed (the window is not resizable) so scripts can
/// click by coordinates; `SettingsLayoutTests` pins the click points that scripts/verify-settings.sh copies.
public enum SettingsLayout {
    public static let size = CGSize(width: 440, height: 380)

    public static let generalHeader = CGRect(x: 20, y: 12, width: 400, height: 18)
    public static let launchAtLogin = CGRect(x: 20, y: 38, width: 300, height: 24)
    public static let equalizerLabel = CGRect(x: 20, y: 94, width: 110, height: 28)

    public static func equalizerSegment(_ mode: EqualizerMode) -> CGRect {
        let index = CGFloat(EqualizerMode.allCases.firstIndex(of: mode) ?? 0)
        return CGRect(x: 140 + 90 * index, y: 94, width: 90, height: 28)
    }

    public static let spotifyHeader = CGRect(x: 20, y: 144, width: 400, height: 18)
    public static let spotifyTitle = CGRect(x: 20, y: 170, width: 400, height: 18)
    public static let spotifyDetail = CGRect(x: 20, y: 190, width: 400, height: 30)
    public static let automationButton = CGRect(x: 20, y: 226, width: 230, height: 28)

    public static let aboutHeader = CGRect(x: 20, y: 270, width: 400, height: 18)
    public static let version = CGRect(x: 20, y: 296, width: 400, height: 16)
    public static let signing = CGRect(x: 20, y: 314, width: 400, height: 16)
    public static let quitButton = CGRect(x: 320, y: 338, width: 100, height: 28)

    /// The checkbox sits at the toggle's leading edge.
    public static var launchAtLoginClick: CGPoint { CGPoint(x: launchAtLogin.minX + 8, y: launchAtLogin.midY) }

    public static func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    public static var allRects: [CGRect] {
        [generalHeader, launchAtLogin, equalizerLabel] + EqualizerMode.allCases.map(equalizerSegment)
            + [spotifyHeader, spotifyTitle, spotifyDetail, automationButton, aboutHeader, version, signing, quitButton]
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test 2>&1 | tail -1`
Expected: starts with `✔ Test run with 256 tests in 20 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShimaCore/SettingsText.swift Sources/ShimaCore/SettingsLayout.swift Tests/ShimaCoreTests/SettingsTextTests.swift
git commit -m "Add Settings texts, the Automation link and the fixed window layout"
```

---

### Task 4: SettingsModel and LoginItemService (PURE, parallel-safe; after Tasks 1-3)

**Files:**
- Create: `Sources/ShimaCore/SettingsModel.swift`
- Create (test double): `Tests/ShimaCoreTests/FakeLoginItemService.swift`
- Test: `Tests/ShimaCoreTests/SettingsModelTests.swift`

**Interfaces:**
- Consumes: `LoginItemStatus`, `LoginItemAction`, `LoginItemMenu`, `LoginItemMenuState` (existing), `AppState`, `SettingsStore`, `SettingsText`, `SettingsLinks`, `SigningSummary`, `EqualizerMode`.
- Produces:
```swift
@MainActor public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func perform(_ action: LoginItemAction) -> Bool        // false only when register or unregister threw
}
public enum SettingsEntry: String, Sendable { case reopen, gear, menu }
public struct LoginItemToggle: Equatable, Sendable {
    public let from: LoginItemStatus, action: LoginItemAction, succeeded: Bool, after: LoginItemStatus
}
@Observable @MainActor public final class SettingsModel {
    public private(set) var loginItemStatus: LoginItemStatus
    public private(set) var loginRegistrationFailed: Bool
    public private(set) var equalizerMode: EqualizerMode
    public private(set) var signingText: String               // "" until the first refresh()
    public let versionText: String
    public var loginItem: LoginItemMenuState { get }          // LoginItemMenu.state(for:registrationFailed:)
    public var spotifyRow: SpotifyStatusRow { get }           // from state.spotifyAvailability (observable)
    public var onOpenURL: (@MainActor (URL) -> Void)?
    public var onQuit: (@MainActor () -> Void)?
    public var onEqualizerModeChange: (@MainActor (EqualizerMode) -> Void)?   // only when the mode changes
    public init(state: AppState, store: SettingsStore, loginItems: LoginItemService, versionText: String,
                readSigning: @escaping @MainActor () -> SigningSummary,
                now: @escaping @MainActor () -> Date = { Date() })
    public func refresh()                                     // re-reads the login status; reads the signature once
    @discardableResult public func toggleLaunchAtLogin() -> LoginItemToggle
    public func setEqualizerMode(_ mode: EqualizerMode)
    public func openAutomationSettings()
    public func quit()
}
```
- `init` reads the stored mode once and writes it to `state.equalizerMode` (design: read once at launch), and reads `loginItems.status` (cheap). The toggle keeps the existing menu semantics: any `perform` returning false sets `loginRegistrationFailed`, which only matters for `notFound` (`LoginItemMenu`).

- [ ] **Step 1: Write the test double and the failing tests**

`Tests/ShimaCoreTests/FakeLoginItemService.swift`:
```swift
@testable import ShimaCore

@MainActor final class FakeLoginItemService: LoginItemService {
    var status: LoginItemStatus
    private(set) var performed: [LoginItemAction] = []
    /// Given the action and the current status: success, and the status afterwards.
    var respond: @MainActor (LoginItemAction, LoginItemStatus) -> (Bool, LoginItemStatus) = { action, status in
        switch action {
        case .register: (true, .enabled)
        case .unregister: (true, .notRegistered)
        case .openSettings, .none: (true, status)
        }
    }

    init(status: LoginItemStatus) { self.status = status }

    func perform(_ action: LoginItemAction) -> Bool {
        performed.append(action)
        let (ok, next) = respond(action, status)
        status = next
        return ok
    }
}
```
`Tests/ShimaCoreTests/SettingsModelTests.swift`:
```swift
import Foundation
import Testing
@testable import ShimaCore

@MainActor final class SettingsTaps {
    var urls: [URL] = []
    var quits = 0
    var signingReads = 0
    var modes: [EqualizerMode] = []
}

@Suite @MainActor struct SettingsModelTests {
    struct Rig {
        let model: SettingsModel
        let state: AppState
        let storage: InMemoryPreferenceStorage
        let login: FakeLoginItemService
        let taps: SettingsTaps
    }

    func make(stored: [String: String] = [:], login status: LoginItemStatus = .notFound,
              signing: SigningSummary = .adHoc) -> Rig {
        let state = AppState(), storage = InMemoryPreferenceStorage(stored)
        let login = FakeLoginItemService(status: status), taps = SettingsTaps()
        let model = SettingsModel(
            state: state, store: SettingsStore(storage: storage), loginItems: login, versionText: "Version 0.0.1 (1)",
            readSigning: { taps.signingReads += 1; return signing },
            now: { ISO8601DateFormatter().date(from: "2026-11-22T00:00:00Z")! })
        model.onOpenURL = { taps.urls.append($0) }
        model.onQuit = { taps.quits += 1 }
        model.onEqualizerModeChange = { taps.modes.append($0) }
        return Rig(model: model, state: state, storage: storage, login: login, taps: taps)
    }

    @Test func initLoadsStoredModeIntoState() {
        let r = make(stored: ["equalizerMode": "off"])
        #expect(r.model.equalizerMode == .off && r.state.equalizerMode == .off && r.storage.writes == 0)
    }
    @Test func setEqualizerModeSavesAndUpdatesState() {
        let r = make()
        r.model.setEqualizerMode(.whenOpen)
        r.model.setEqualizerMode(.whenOpen)
        #expect(r.storage.values["equalizerMode"] == "whenOpen" && r.storage.writes == 1)
        #expect(r.state.equalizerMode == .whenOpen && r.model.equalizerMode == .whenOpen && r.taps.modes == [.whenOpen])
    }
    @Test func refreshReadsLoginStatus() {
        let r = make(login: .notRegistered)
        r.login.status = .enabled
        r.model.refresh()
        #expect(r.model.loginItemStatus == .enabled && r.model.loginItem.isOn)
    }
    @Test func toggleRegistersFromNotFound() {
        let r = make(login: .notFound)
        #expect(r.model.toggleLaunchAtLogin() == LoginItemToggle(from: .notFound, action: .register, succeeded: true, after: .enabled))
        #expect(r.login.performed == [.register])
        #expect(r.model.loginItem == LoginItemMenuState(title: "Launch at login", isOn: true, isEnabled: true))
    }
    @Test func toggleUnregistersWhenEnabled() {
        let r = make(login: .enabled)
        #expect(r.model.toggleLaunchAtLogin() == LoginItemToggle(from: .enabled, action: .unregister, succeeded: true, after: .notRegistered))
        #expect(!r.model.loginItem.isOn)
    }
    @Test func failedRegisterMakesItUnavailable() {
        let r = make(login: .notFound)
        r.login.respond = { _, status in (false, status) }
        #expect(r.model.toggleLaunchAtLogin() == LoginItemToggle(from: .notFound, action: .register, succeeded: false, after: .notFound))
        #expect(r.model.loginRegistrationFailed)
        #expect(r.model.loginItem == LoginItemMenuState(title: "Launch at login (unavailable)", isOn: false, isEnabled: false))
        #expect(r.model.toggleLaunchAtLogin().action == .none && r.login.performed == [.register])
    }
    @Test func requiresApprovalOpensSystemSettings() {
        let r = make(login: .requiresApproval)
        #expect(r.model.toggleLaunchAtLogin() == LoginItemToggle(from: .requiresApproval, action: .openSettings, succeeded: true, after: .requiresApproval))
        #expect(r.login.performed == [.openSettings])
    }
    @Test func spotifyRowFollowsAppState() {
        let r = make()
        #expect(r.model.spotifyRow.kind == .notRunning)
        r.state.spotifyAvailability = .permissionDenied
        #expect(r.model.spotifyRow == SettingsText.spotifyRow(.permissionDenied))
    }
    @Test func openAutomationSettingsUsesExactURL() {
        let r = make()
        r.model.openAutomationSettings()
        #expect(r.taps.urls.map(\.absoluteString) == ["x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"])
    }
    @Test func quitCallsHandler() {
        let r = make()
        r.model.quit()
        #expect(r.taps.quits == 1)
    }
    @Test func signingIsReadOnceOnFirstRefresh() {
        let r = make(signing: .adHoc)
        #expect(r.model.signingText == "" && r.taps.signingReads == 0)
        r.model.refresh()
        r.model.refresh()
        #expect(r.taps.signingReads == 1 && r.model.signingText == "Signed ad hoc (no certificate)")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter SettingsModelTests 2>&1 | grep -m1 error:`
Expected: `error: cannot find type 'LoginItemService' in scope` (or `SettingsModel`).

- [ ] **Step 3: Implement**

`Sources/ShimaCore/SettingsModel.swift`:
```swift
import Foundation
import Observation

@MainActor public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    /// Returns false only when register or unregister threw.
    func perform(_ action: LoginItemAction) -> Bool
}

public enum SettingsEntry: String, Sendable {
    case reopen, gear, menu
}

public struct LoginItemToggle: Equatable, Sendable {
    public let from: LoginItemStatus
    public let action: LoginItemAction
    public let succeeded: Bool
    public let after: LoginItemStatus

    public init(from: LoginItemStatus, action: LoginItemAction, succeeded: Bool, after: LoginItemStatus) {
        self.from = from
        self.action = action
        self.succeeded = succeeded
        self.after = after
    }
}

/// The settings shared by the status menu and the Settings window. No polling: `refresh()` runs when the
/// window or the menu opens; the Spotify row follows `AppState` through Observation.
@Observable @MainActor public final class SettingsModel {
    public private(set) var loginItemStatus: LoginItemStatus
    public private(set) var loginRegistrationFailed = false
    public private(set) var equalizerMode: EqualizerMode
    public private(set) var signingText = ""
    public let versionText: String

    public var loginItem: LoginItemMenuState {
        LoginItemMenu.state(for: loginItemStatus, registrationFailed: loginRegistrationFailed)
    }
    public var spotifyRow: SpotifyStatusRow { SettingsText.spotifyRow(state.spotifyAvailability) }

    @ObservationIgnored public var onOpenURL: (@MainActor (URL) -> Void)?
    @ObservationIgnored public var onQuit: (@MainActor () -> Void)?
    @ObservationIgnored public var onEqualizerModeChange: (@MainActor (EqualizerMode) -> Void)?

    @ObservationIgnored private let state: AppState
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let loginItems: LoginItemService
    @ObservationIgnored private let readSigning: @MainActor () -> SigningSummary
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var signingRead = false

    public init(state: AppState, store: SettingsStore, loginItems: LoginItemService, versionText: String,
                readSigning: @escaping @MainActor () -> SigningSummary,
                now: @escaping @MainActor () -> Date = { Date() }) {
        self.state = state
        self.store = store
        self.loginItems = loginItems
        self.versionText = versionText
        self.readSigning = readSigning
        self.now = now
        self.loginItemStatus = loginItems.status
        let mode = store.equalizerMode
        self.equalizerMode = mode
        state.equalizerMode = mode
    }

    public func refresh() {
        loginItemStatus = loginItems.status
        if !signingRead {
            signingRead = true
            signingText = SettingsText.signing(readSigning(), now: now())
        }
    }

    @discardableResult
    public func toggleLaunchAtLogin() -> LoginItemToggle {
        let from = loginItems.status
        let action = LoginItemMenu.action(for: from, registrationFailed: loginRegistrationFailed)
        var succeeded = true
        if action != .none {
            succeeded = loginItems.perform(action)
            if !succeeded { loginRegistrationFailed = true }
        }
        let after = loginItems.status
        loginItemStatus = after
        return LoginItemToggle(from: from, action: action, succeeded: succeeded, after: after)
    }

    public func setEqualizerMode(_ mode: EqualizerMode) {
        store.setEqualizerMode(mode)
        guard mode != equalizerMode else { return }
        equalizerMode = mode
        state.equalizerMode = mode
        onEqualizerModeChange?(mode)
    }

    public func openAutomationSettings() { onOpenURL?(SettingsLinks.automation) }

    public func quit() { onQuit?() }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test 2>&1 | tail -1`
Expected: starts with `✔ Test run with 267 tests in 21 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShimaCore/SettingsModel.swift Tests/ShimaCoreTests/FakeLoginItemService.swift Tests/ShimaCoreTests/SettingsModelTests.swift
git commit -m "Add SettingsModel shared by the status menu and the Settings window"
```

---

### Task 5: Gear rect and narrower title in NowPlayingLayout (PURE, parallel-safe)

**Files:**
- Modify: `Sources/ShimaCore/NowPlayingLayout.swift`
- Test: `Tests/ShimaCoreTests/NowPlayingLayoutTests.swift`

**Interfaces:**
- Produces (in `NowPlayingLayout`):
```swift
public static let titleWidth: CGFloat = 200
public static var titleRect: CGRect                  // (116, 44, 200, 18)
public static let settingsButton: CGRect             // (322, 38, 24, 24), island-local top-left
public static func settingsButtonCenter(notchMidX: CGFloat, topY: CGFloat) -> CGPoint   // (889.5, 50) on this Mac
```
- Plan note 2: "top-right of the expanded island" literally is the top strip right of the notch (y 0..32), where the status items live (on this macOS they are `Control Center` windows at the island's window level 25; which one gets a click there is not known). The gear sits just below the 33 pt menu bar instead, right of a title narrowed from 230 to 200 pt. The artist, progress and controls keep the full column.

- [ ] **Step 1: Write the failing tests** (append inside `NowPlayingLayoutTests`)

```swift
    @Test func settingsButtonSitsTopRightBelowTheMenuBar() {
        let g = NowPlayingLayout.settingsButton
        #expect(g == CGRect(x: 322, y: 38, width: 24, height: 24))
        #expect(island.contains(g) && g.minY >= 34 && g.maxX == NowPlayingLayout.column.maxX)
    }
    @Test func settingsButtonClearsTitleArtworkAndControls() {
        let g = NowPlayingLayout.settingsButton
        #expect(NowPlayingLayout.titleRect == CGRect(x: 116, y: 44, width: 200, height: 18))
        for r in [NowPlayingLayout.titleRect, NowPlayingLayout.artwork] + SpotifyCommand.allCases.map(NowPlayingLayout.controlRect) {
            #expect(!g.intersects(r))
        }
        #expect(NowPlayingLayout.titleRect.maxX + 6 == g.minX && g.maxY <= NowPlayingLayout.artistTop)
    }
    @Test func settingsButtonCenterOnThisMac() {
        #expect(NowPlayingLayout.settingsButtonCenter(notchMidX: 735.5, topY: 0) == CGPoint(x: 889.5, y: 50))
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter NowPlayingLayoutTests 2>&1 | grep -m1 error:`
Expected: `error: type 'NowPlayingLayout' has no member 'settingsButton'`.

- [ ] **Step 3: Implement** (in `NowPlayingLayout`, after `progressHeight`)

```swift
    /// The title is narrower than the column so the settings gear fits at the top right.
    public static let titleWidth: CGFloat = 200
    public static var titleRect: CGRect { CGRect(x: column.minX, y: titleTop, width: titleWidth, height: 18) }

    /// Settings gear: top right of the open island, below the notch strip and the 33 pt menu bar
    /// (status items there are other windows at the island's level).
    public static let settingsButton = CGRect(x: 322, y: 38, width: 24, height: 24)

    /// Centre in global top-left CG points; topY is the screen's top edge.
    public static func settingsButtonCenter(notchMidX: CGFloat, topY: CGFloat) -> CGPoint {
        CGPoint(x: notchMidX - IslandLayout.expanded.width / 2 + settingsButton.midX, y: topY + settingsButton.midY)
    }
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test 2>&1 | tail -1`
Expected: starts with `✔ Test run with 270 tests in 21 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShimaCore/NowPlayingLayout.swift Tests/ShimaCoreTests/NowPlayingLayoutTests.swift
git commit -m "Add the island settings gear rect and narrow the title to fit it"
```

---

### Task 6: run.sh kills by pid; drive.swift keys; shima-windows --settings (SCRIPT, controller, parallel with Codex)

**Files:**
- Modify: `scripts/run.sh`, `scripts/drive.swift`, `scripts/shima-windows.swift`

**Interfaces:**
- Produces:
  - `scripts/run.sh`: replaces `pkill -x Shima` with a loop that kills only pids whose `ps -o command=` starts with `$REPO/dist/Shima.app/` and waits up to 3 s for them; for every other Shima it prints `Leaving Shima pid N alone (runs from elsewhere: CMD)` and `warning: another Shima is running; its island overlaps this one`.
  - `scripts/drive.swift`: `key NAME` for `esc`, `tab`, `space`, `return`, `cmd-w`, `cmd-comma`, posting down, 20 ms, up (M1 finding: Esc without a gap did not close the Apple menu); an unknown key prints `unknown key: NAME` and exits 2.
  - `scripts/shima-windows.swift --settings [pid]`: lists on-screen windows owned by `Shima` (and by that pid when given) at layer 0, prints `settings windows: N` then `settings window x=… y=… w=… h=…` per window; exit 0 when N == 1, 1 when 0, 3 when more. Runs before the island lookup (works with the island hidden).

- [ ] **Step 1: `run.sh`**

Replace the line `pkill -x Shima 2>/dev/null || true` with:
```bash
REPO="$PWD"
# Stop only this checkout's dist build, by pid. Codex's worktree build and the installed app keep running.
mine() { for p in $(pgrep -x Shima || true); do [[ "$(ps -o command= -p "$p" || true)" == "$REPO/dist/Shima.app/"* ]] && echo "$p"; done; }
for pid in $(mine); do kill "$pid"; done
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -z "$(mine)" ]] && break; sleep 0.3; done
for pid in $(pgrep -x Shima || true); do
  echo "Leaving Shima pid $pid alone (runs from elsewhere: $(ps -o command= -p "$pid" || true))"
  echo "warning: another Shima is running; its island overlaps this one"
done
```

- [ ] **Step 2: `drive.swift` keys**

Replace the `case "key" where w.count > 1 && w[1] == "esc":` case with:
```swift
    case "key" where w.count > 1:
        let keys: [String: (CGKeyCode, CGEventFlags)] = [
            "esc": (53, []), "tab": (48, []), "space": (49, []), "return": (36, []),
            "cmd-w": (13, .maskCommand), "cmd-comma": (43, .maskCommand)]
        guard let key = keys[w[1]] else { stamp("unknown key: \(w[1])"); exit(2) }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: key.0, keyDown: down)
            e?.flags = key.1
            e?.post(tap: .cghidEventTap)
            if down { wait(20) }
        }
```
Update the usage comment at the top to list the keys.

- [ ] **Step 3: `shima-windows.swift --settings`**

After the `--menus` block (before `var best`), add:
```swift
if mode == "--settings" {
    // The Settings window is Shima's only layer-0 window (the island is layer 25, menus 101).
    // Titles are unreadable without Screen Recording, so match owner, pid and layer.
    let wantPID = CommandLine.arguments.dropFirst(2).first.flatMap { Int32($0) }
    let mine = info.filter {
        ($0[kCGWindowOwnerName as String] as? String) == "Shima"
            && (($0[kCGWindowLayer as String] as? Int) ?? -1) == 0
            && (wantPID == nil || ($0[kCGWindowOwnerPID as String] as? Int32) == wantPID)
    }
    print("settings windows: \(mine.count)")
    for w in mine { if let r = rectOf(w) { print("settings window \(fmt(r))") } }
    exit(mine.count == 1 ? 0 : (mine.count == 0 ? 1 : 3))
}
```
Add `--settings [pid]` to the usage line in `scripts/verify-alignment.sh`'s comment.

- [ ] **Step 4: Verify (AUTOMATED, about 20 s, no pointer)**

1. `grep -rn 'pkill' scripts` → no output.
2. `SHIMA_FAKE_SPOTIFY=paused scripts/run.sh >/dev/null && sleep 2 && a="$(pgrep -lx Shima)" && SHIMA_FAKE_SPOTIFY=paused scripts/run.sh >/dev/null && sleep 2 && b="$(pgrep -lx Shima)" && echo "before: $a" && echo "after: $b"` → one `Shima` line each, different pids (the old dist instance was replaced; any instance from elsewhere is listed by run.sh as left alone).
3. `swift scripts/drive.swift "key bogus"; echo "exit $?"` → `unknown key: bogus`, `exit 2`.
4. `swift scripts/shima-windows.swift --settings "$(pgrep -nx Shima)"; echo "exit $?"` → `settings windows: 0`, `exit 1`.
5. Stop the instance by pid: `kill "$(pgrep -nx Shima)"` only if `ps -o command= -p "$(pgrep -nx Shima)"` shows this checkout's `dist/Shima.app`.

- [ ] **Step 5: Commit**

```bash
git add scripts/run.sh scripts/drive.swift scripts/shima-windows.swift scripts/verify-alignment.sh
git commit -m "Stop only this checkout's Shima by pid; add keys to drive.swift and a settings window listing"
```

---

### Task 7: Settings plumbing in the app: model, menu via the model, fake commands (GLUE, sequential; after the merge)

**Files:**
- Modify: `Sources/Shima/Log.swift`, `Sources/Shima/LoginItem.swift`, `Sources/Shima/SpotifyService.swift`, `Sources/Shima/AppDelegate.swift`
- Create: `Sources/Shima/SigningInfo.swift`

**Interfaces:**
- Consumes: `SettingsModel`, `SettingsStore`, `UserDefaultsPreferenceStorage.forShima`, `SettingsText.version`, `LoginItemService`, `SigningSummary`, `EqualizerMode`.
- Produces:
  - `Log.settings = Logger(subsystem: "local.shima", category: "settings")`.
  - `@MainActor final class SystemLoginItemService: LoginItemService` in `LoginItem.swift`: `status` returns `LoginItem.status`, `perform` returns `LoginItem.perform(action)`.
  - `enum SigningInfo { static func read(bundleURL: URL = Bundle.main.bundleURL) -> SigningSummary }` (code below).
  - `SpotifyService`: `var onFakeEqualizerMode: (@MainActor (EqualizerMode) -> Void)?`; fake commands `denied` (`receive(.permissionDenied)`), `allowed` (`fake?.refresh()`: a script reading turns `permissionDenied` back into `running`), `eq-mode-<raw>` (calls `onFakeEqualizerMode`), each logged `fake <cmd>`; unknown stays `fake unknown <cmd>`.
  - `AppDelegate`: a lazy `settings: SettingsModel` (first touched at the top of `applicationDidFinishLaunching`, which loads the stored mode into `AppState`), log lines `settings eq mode=<mode> loaded` (launch) and `settings eq mode=<mode> saved` (via `onEqualizerModeChange`), `onOpenURL` honouring `SHIMA_SETTINGS_DRY_OPEN` (log `settings open url=<url> dryRun=<bool>`, open only when not dry), `onQuit` (log `settings quit`, then `NSApp.terminate(nil)`). The status menu reads and toggles through `settings` (its `loginRegistrationFailed` property is removed); the `menu launchAtLogin …` log lines keep their wording.

- [ ] **Step 1: Implement**

`Sources/Shima/SigningInfo.swift`:
```swift
import Foundation
import Security
import ShimaCore

/// Reads Shima.app's own code signature (local, no network). Called once, on the first settings refresh.
enum SigningInfo {
    static func read(bundleURL: URL = Bundle.main.bundleURL) -> SigningSummary {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return .unreadable }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return .unreadable }
        guard let certificates = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { return .adHoc }
        let name = (SecCertificateCopySubjectSummary(leaf) as String?) ?? "Unknown"
        return .certificate(commonName: name, notAfter: notAfter(leaf))
    }

    private static func notAfter(_ certificate: SecCertificate) -> Date? {
        if #available(macOS 15, *) {
            return SecCertificateCopyNotValidAfterDate(certificate) as Date?
        }
        let key = kSecOIDX509V1ValidityNotAfter
        guard let values = SecCertificateCopyValues(certificate, [key] as CFArray, nil) as? [String: Any],
              let entry = values[key as String] as? [String: Any],
              let seconds = entry[kSecPropertyKeyValue as String] as? NSNumber else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds.doubleValue)
    }
}
```
`AppDelegate.swift` (whole file after this task):
```swift
import AppKit
import ShimaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let islandController = IslandPanelController()
    private lazy var spotify = SpotifyService(state: islandController.state, media: islandController.media)
    private let environment = ProcessInfo.processInfo.environment
    private lazy var settings = SettingsModel(
        state: islandController.state,
        store: SettingsStore(storage: UserDefaultsPreferenceStorage.forShima(bundleIdentifier: Bundle.main.bundleIdentifier)),
        loginItems: SystemLoginItemService(),
        versionText: SettingsText.version(
            short: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String),
        readSigning: { SigningInfo.read() })
    private var statusItem: NSStatusItem?
    private let loginItemMenuItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLoginItem), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.settings.info("settings eq mode=\(self.settings.equalizerMode.rawValue, privacy: .public) loaded")
        settings.onEqualizerModeChange = { mode in
            Log.settings.info("settings eq mode=\(mode.rawValue, privacy: .public) saved")
        }
        let dryOpen = environment["SHIMA_SETTINGS_DRY_OPEN"] != nil
        settings.onOpenURL = { url in
            Log.settings.info("settings open url=\(url.absoluteString, privacy: .public) dryRun=\(dryOpen, privacy: .public)")
            if !dryOpen { NSWorkspace.shared.open(url) }
        }
        settings.onQuit = {
            Log.settings.info("settings quit")
            NSApp.terminate(nil)
        }
        setUpStatusItem()
        showPanel()
        spotify.onLiveChange = { [weak self] in self?.islandController.setLive($0) }
        spotify.onFakeEqualizerMode = { [weak self] in self?.settings.setEqualizerMode($0) }
        islandController.onIslandOpened = { [weak self] in self?.spotify.islandOpened() }
        islandController.onCommand = { [weak self] in self?.spotify.perform($0) }
        spotify.start()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func appBecameActive() { Log.focus.error("app became active") }

    @objc private func screensChanged() { showPanel() }

    private func showPanel() {
        islandController.place(on: ScreenLocator.target())
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "shima")
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        loginItemMenuItem.target = self
        menu.addItem(loginItemMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit shima", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        settings.refresh()
        Log.menu.info("menu launchAtLogin status=\(String(describing: self.settings.loginItemStatus), privacy: .public)")
        let state = settings.loginItem
        loginItemMenuItem.title = state.title
        loginItemMenuItem.state = state.isOn ? .on : .off
        loginItemMenuItem.isEnabled = state.isEnabled
    }

    @objc private func toggleLoginItem() {
        let r = settings.toggleLaunchAtLogin()
        Log.menu.info("menu launchAtLogin toggle from=\(String(describing: r.from), privacy: .public) action=\(String(describing: r.action), privacy: .public)")
        Log.menu.info("menu launchAtLogin status after=\(String(describing: r.after), privacy: .public)")
    }
}
```
`SpotifyService.swift`: add `var onFakeEqualizerMode: (@MainActor (EqualizerMode) -> Void)?` next to `onLiveChange`, and in `handleFake` before `default:`:
```swift
        case "denied": Log.spotify.info("fake denied"); receive(.permissionDenied)
        case "allowed": Log.spotify.info("fake allowed"); fake?.refresh()
        case let c where c.hasPrefix("eq-mode-"):
            if let mode = EqualizerMode(rawValue: String(c.dropFirst("eq-mode-".count))) {
                Log.spotify.info("fake \(c, privacy: .public)")
                onFakeEqualizerMode?(mode)
            } else {
                Log.spotify.info("fake unknown \(c, privacy: .public)")
            }
```
`LoginItem.swift`: append
```swift
@MainActor
final class SystemLoginItemService: LoginItemService {
    var status: LoginItemStatus { LoginItem.status }
    func perform(_ action: LoginItemAction) -> Bool { LoginItem.perform(action) }
}
```
`Log.swift`: add `static let settings = Logger(subsystem: "local.shima", category: "settings")`.

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | grep -E 'warning:|error:|Build complete' | tail -3`
Expected: `Build complete!` and no warning lines from `Sources/Shima` (a Sendable warning on `SecCertificate`/`NSRunningApplication` means following the pattern already used in `SpotifyObservers.swift`).

- [ ] **Step 3: Fake commands and persistence (AUTOMATED, about 1 min, no pointer)**

Run:
```bash
SHIMA_FAKE_SPOTIFY=playing scripts/run.sh >/dev/null && sleep 2
scripts/with-log.sh .build/s7.log -- swift scripts/drive.swift "fake eq-mode-off; sleep 300; fake denied; sleep 300; fake allowed; sleep 300" >/dev/null
grep -E 'settings eq|fake (eq-mode|denied|allowed)|availabilityChanged' .build/s7.log | sed -E 's/^.*\] //'
defaults read local.shima equalizerMode
scripts/with-log.sh .build/s7b.log -- bash -c 'SHIMA_FAKE_SPOTIFY=playing scripts/run.sh >/dev/null; sleep 3' && grep -E 'settings eq mode=[a-zA-Z]+ loaded' .build/s7b.log | sed -E 's/^.*\] //'
swift scripts/drive.swift "fake eq-mode-animated" >/dev/null && sleep 0.5 && defaults read local.shima equalizerMode
```
Expected, in order: `fake eq-mode-off`, `settings eq mode=off saved`, `fake denied`, a `spotify changes` line containing `availabilityChanged` and `permissionDenied`, `fake allowed`, a `spotify changes` line containing `availabilityChanged` and `running`; then `off`; then `settings eq mode=off loaded` (after the relaunch); then `animated`. The `pgrep -x Spotify` pid is the same before and after.

- [ ] **Step 4: Status menu unchanged (AUTOMATED, 5 s pointer)**

The menu's coordinates come from Task 11's log; until then use M1's `872 16` and accept a miss. Run: `scripts/with-log.sh .build/s7c.log -- swift scripts/drive.swift "click 872 16; sleep 600; key esc" >/dev/null; grep -E 'menu launchAtLogin status=' .build/s7c.log | sed -E 's/^.*\] //'`
Expected: `menu launchAtLogin status=notFound` (or `notRegistered`) when the click hit Shima's capsule; nothing when another app's item was hit (record which, no failure). Do not click "Launch at login" on the `dist/` build.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shima/Log.swift Sources/Shima/LoginItem.swift Sources/Shima/SigningInfo.swift Sources/Shima/SpotifyService.swift Sources/Shima/AppDelegate.swift
git commit -m "Wire SettingsModel into the app: menu login item, stored equalizer mode, fake denied/allowed/eq-mode"
```

---

### Task 8: Equalizer mode in the wings and the open island (GLUE, sequential)

**Files:**
- Modify: `Sources/Shima/WingsView.swift`, `scripts/view-layout-check.swift`

**Interfaces:**
- Consumes: `EqualizerPolicy`, `AppState.equalizerMode`, `media.equalizerFrozen`.
- Produces: `WingsView` computes `animating` with `EqualizerPolicy.isAnimating(state.equalizerMode, island: state.mode, live: state.live, content: state.content, playing: state.nowPlaying?.state == .playing, frozen: media.equalizerFrozen)`; the mini artwork's opacity is `state.live && state.mode == .collapsed`, the equalizer's is `EqualizerPolicy.isVisible(island: state.mode, live: state.live, content: state.content)`; the `HStack` keeps its explicit `notchWidth + 66 x 32` frame and loses the root `.opacity`. `EqualizerView` stays unconditional. `view-layout-check.swift` checks the new expanded state and runs the now-playing checks by default (`--now-playing` still accepted).

- [ ] **Step 1: Update the layout check first**

In `scripts/view-layout-check.swift`:
1. `let expectsNowPlaying = CommandLine.arguments.contains("--now-playing")` becomes `let expectsNowPlaying = true // --now-playing is the default since the Settings milestone; the flag is still accepted` and delete the `else` branch that checks `expanded mini artwork must be hidden` at x 76.5.
2. Replace `check(expanded.rows(in: 290..<320, matching: isGreen).isEmpty, "expanded equalizer must be hidden")` with:
```swift
        check(expanded.rows(in: 290..<320, ys: 0..<32, matching: isGreen) == 9..<23,
              "expanded equalizer (track shown) must sit right of the notch, rows 9..<23")
        check(expanded.rows(in: 82..<102, ys: 0..<32, matching: isMagenta).isEmpty, "expanded mini artwork must be hidden")
        state.spotifyAvailability = .notRunning
        host.layoutSubtreeIfNeeded()
        let notRunning = render(host)
        check(notRunning.rows(in: 290..<320, ys: 0..<32, matching: isGreen).isEmpty, "expanded equalizer must be hidden without a track")
        state.spotifyAvailability = .running
        host.layoutSubtreeIfNeeded()
```
3. The expanded print line becomes `print("expanded 396x173: silhouette 0..<165, equalizer 9..<23 with a track and hidden without, mini artwork hidden, artwork 44..<132 PASS")`.

Run: `scripts/verify-view-layout.sh 2>&1 | tail -2`
Expected (fails before the view change): `FAIL: expanded equalizer (track shown) must sit right of the notch, rows 9..<23`.

- [ ] **Step 2: Implement `WingsView`**

```swift
/// Kept in the hierarchy even while hidden so the equalizer retains its layer identity.
/// The equalizer stays at the same spot right of the notch while the island opens (Settings: equalizer mode).
struct WingsView: View {
    let state: AppState
    let media: IslandMedia
    let notchWidth: CGFloat

    private var equalizerVisible: Bool {
        EqualizerPolicy.isVisible(island: state.mode, live: state.live, content: state.content)
    }

    private var animating: Bool {
        EqualizerPolicy.isAnimating(state.equalizerMode, island: state.mode, live: state.live, content: state.content,
                                    playing: state.nowPlaying?.state == .playing, frozen: media.equalizerFrozen)
    }

    var body: some View {
        HStack(spacing: 0) {
            miniArtwork
                .frame(width: IslandLayout.liveWingWidth, height: 32)
                .opacity(state.live && state.mode == .collapsed ? 1 : 0)
            Color.clear
                .frame(width: notchWidth, height: 32)
            EqualizerView(animating: animating)
                .frame(width: NowPlayingLayout.equalizer.width, height: NowPlayingLayout.equalizer.height)
                .frame(width: IslandLayout.liveWingWidth, height: 32)
                .opacity(equalizerVisible ? 1 : 0)
        }
        .frame(width: notchWidth + 2 * IslandLayout.liveWingWidth, height: 32)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    // miniArtwork unchanged
}
```

- [ ] **Step 3: Offscreen layout check**

Run: `scripts/verify-view-layout.sh 2>&1 | tail -5`
Expected:
```
live 245x32: black 0..<32, artwork 6..<26, equalizer 9..<23 PASS
expanded 396x173: silhouette 0..<165, equalizer 9..<23 with a track and hidden without, mini artwork hidden, artwork 44..<132 PASS
not-live 179x32: black 0..<32, no wings content PASS
cacheDisplay pixel checks PASS; no window shown, no image file written
```
(and the `live equalizer bounds: (220.5, 9.0, 16.0, 14.0)` line above them).

- [ ] **Step 4: Modes in the running app (AUTOMATED, announce: about 15 s of pointer)**

Screen unlocked and awake (`caffeinate -dimsu &`). Run:
```bash
SHIMA_FAKE_SPOTIFY=playing scripts/run.sh >/dev/null && sleep 2
scripts/with-log.sh .build/s8.log -- swift scripts/drive.swift "move 735 400; fake playing; sleep 500; fake eq-mode-off; sleep 400; fake eq-mode-whenOpen; sleep 400; move 735 16; sleep 900; move 735 400; sleep 1500; fake eq-mode-animated; sleep 400; move 735 16; sleep 900; move 735 400; sleep 1500" >/dev/null
grep -E 'eq (animating|frozen)|settings eq|hover (dwelling -> expanded|leaving -> collapsing)' .build/s8.log | sed -E 's/^.*\] //'
```
Expected, in order: `settings eq mode=off saved`, `eq frozen anims=0`; `settings eq mode=whenOpen saved` with no eq line after it; `hover dwelling -> expanded`, `eq animating anims=4`; `hover leaving -> collapsing`, `eq frozen anims=0`; `settings eq mode=animated saved`, `eq animating anims=4`; the second `hover dwelling -> expanded` and `hover leaving -> collapsing` with **no** eq line between or after them (animated keeps running while open). Any `eq frozen` without a mode or hover reason means the screen locked: re-run.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shima/WingsView.swift scripts/view-layout-check.swift
git commit -m "Drive the equalizer from the equalizer mode and keep it visible in the open island"
```

---

### Task 9: SettingsView, SettingsWindowController and the reopen entry (GLUE, sequential)

**Files:**
- Create: `Sources/Shima/SettingsView.swift`, `Sources/Shima/SettingsWindowController.swift`, `docs/superpowers/settings-acceptance.md` (decision section only; Task 14 completes it)
- Modify: `Sources/Shima/AppDelegate.swift`

**Interfaces:**
- Consumes: `SettingsModel`, `SettingsLayout`, `SettingsText`, `SettingsEntry`, `EqualizerMode`.
- Produces:
  - `struct SettingsView: View` with `let model: SettingsModel`, `let onToggleLogin: @MainActor () -> Void`, `let onEqualizerMode: @MainActor (EqualizerMode) -> Void`, `let onSpotifyRow: @MainActor (SpotifyStatusKind) -> Void`; every control at its `SettingsLayout` rect; `.onChange(of: model.spotifyRow.kind, initial: true)` calls `onSpotifyRow` (logs `settings spotify row=<kind>`).
  - `final class SettingsWindow: NSWindow` (Cmd-W closes).
  - `@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate` with `init(model:onToggleLogin:)` and `func show(via entry: SettingsEntry)`. Logs: `settings window created` (once per process), `settings refresh loginItem=<status> spotify=<kind> eq=<mode> version="…" signing="…"` (each show), `settings opened via <entry> created=<bool> active=<bool> key=<bool>` (next run-loop turn), `settings closed policy=<accessory|regular|prohibited> restored=<bundle id|none> active=<bool>`.
  - `AppDelegate`: `private lazy var settingsWindow`, touched in `applicationDidFinishLaunching` (so its deactivation observer exists before the first reopen); `applicationShouldHandleReopen(_:hasVisibleWindows:)` shows the window via `.reopen` and returns `false`; window login toggles log `settings loginItem toggle from=<s> action=<a> ok=<bool> after=<s>`.
- Activation (plan note 5): first try the cooperative macOS 14 path, `.accessory` throughout (no Dock icon). Step 4 decides whether a fallback is needed.

- [ ] **Step 1: Implement**

`Sources/Shima/SettingsView.swift`:
```swift
import SwiftUI
import ShimaCore

/// Fixed layout (SettingsLayout) so scripts can click by coordinates. No timers; the Spotify row
/// follows AppState through Observation.
struct SettingsView: View {
    let model: SettingsModel
    let onToggleLogin: @MainActor () -> Void
    let onEqualizerMode: @MainActor (EqualizerMode) -> Void
    let onSpotifyRow: @MainActor (SpotifyStatusKind) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            header("General", SettingsLayout.generalHeader)
            Toggle(model.loginItem.title, isOn: Binding(get: { model.loginItem.isOn }, set: { _ in onToggleLogin() }))
                .toggleStyle(.checkbox)
                .disabled(!model.loginItem.isEnabled)
                .place(SettingsLayout.launchAtLogin)
            Text("Equalizer").place(SettingsLayout.equalizerLabel)
            ForEach(EqualizerMode.allCases, id: \.self) { mode in
                segment(mode).place(SettingsLayout.equalizerSegment(mode))
            }

            header("Spotify", SettingsLayout.spotifyHeader)
            Text(model.spotifyRow.title).font(.system(size: 13, weight: .medium)).place(SettingsLayout.spotifyTitle)
            Text(model.spotifyRow.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                .lineLimit(2).place(SettingsLayout.spotifyDetail)
            automationButton.place(SettingsLayout.automationButton)

            header("About", SettingsLayout.aboutHeader)
            Text(model.versionText).font(.system(size: 12)).place(SettingsLayout.version)
            Text(model.signingText).font(.system(size: 12)).foregroundStyle(.secondary).place(SettingsLayout.signing)
            Button { model.quit() } label: {
                Text(SettingsText.quitButton).frame(width: SettingsLayout.quitButton.width - 16)
            }
            .place(SettingsLayout.quitButton)
        }
        .frame(width: SettingsLayout.size.width, height: SettingsLayout.size.height, alignment: .topLeading)
        .onChange(of: model.spotifyRow.kind, initial: true) { _, kind in onSpotifyRow(kind) }
    }

    private func header(_ title: String, _ rect: CGRect) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold)).place(rect)
    }

    private func segment(_ mode: EqualizerMode) -> some View {
        let selected = model.equalizerMode == mode
        return Button { onEqualizerMode(mode) } label: {
            Text(mode.title)
                .font(.system(size: 12))
                .frame(width: 86, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor : Color.secondary.opacity(0.15)))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var automationButton: some View {
        let label = Text(model.spotifyRow.buttonTitle).frame(width: SettingsLayout.automationButton.width - 16)
        if model.spotifyRow.buttonProminent {
            Button { model.openAutomationSettings() } label: { label }.buttonStyle(.borderedProminent)
        } else {
            Button { model.openAutomationSettings() } label: { label }.buttonStyle(.bordered)
        }
    }
}

private extension View {
    func place(_ r: CGRect) -> some View {
        frame(width: r.width, height: r.height, alignment: .leading).position(x: r.midX, y: r.midY)
    }
}
```
`Sources/Shima/SettingsWindowController.swift`:
```swift
import AppKit
import SwiftUI
import ShimaCore

/// Cmd-W closes the window (an accessory app has no main menu to provide it).
final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// The one Settings window (design 2026-11-22). Created on first show, then only ordered out and in.
/// Showing it is the only place shima activates itself; closing it hands activation back.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private let onToggleLogin: @MainActor () -> Void
    private var window: SettingsWindow?
    /// The last other app that lost activation: the one to hand focus back to on close.
    private var lastOtherApp: NSRunningApplication?

    init(model: SettingsModel, onToggleLogin: @escaping @MainActor () -> Void) {
        self.model = model
        self.onToggleLogin = onToggleLogin
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appDeactivated(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
    }

    func show(via entry: SettingsEntry) {
        let created = window == nil
        let window = self.window ?? makeWindow()
        self.window = window
        model.refresh()
        Log.settings.info("settings refresh loginItem=\(String(describing: self.model.loginItemStatus), privacy: .public) spotify=\(self.model.spotifyRow.kind.rawValue, privacy: .public) eq=\(self.model.equalizerMode.rawValue, privacy: .public) version=\"\(self.model.versionText, privacy: .public)\" signing=\"\(self.model.signingText, privacy: .public)\"")
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak window] in
            Log.settings.info("settings opened via \(entry.rawValue, privacy: .public) created=\(created, privacy: .public) active=\(NSApp.isActive, privacy: .public) key=\(window?.isKeyWindow ?? false, privacy: .public)")
        }
    }

    func windowWillClose(_ notification: Notification) {
        var restored = "none"
        if NSApp.isActive, let app = lastOtherApp, !app.isTerminated {
            NSApp.yieldActivation(to: app)
            if app.activate(from: .current, options: []) {
                restored = app.bundleIdentifier ?? "pid \(app.processIdentifier)"
            }
        }
        let restoredName = restored
        DispatchQueue.main.async {
            let policy: String = switch NSApp.activationPolicy() {
            case .accessory: "accessory"
            case .regular: "regular"
            case .prohibited: "prohibited"
            @unknown default: "unknown"
            }
            Log.settings.info("settings closed policy=\(policy, privacy: .public) restored=\(restoredName, privacy: .public) active=\(NSApp.isActive, privacy: .public)")
        }
    }

    @objc nonisolated private func appDeactivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        MainActor.assumeIsolated { lastOtherApp = app }
    }

    private func makeWindow() -> SettingsWindow {
        let w = SettingsWindow(contentRect: NSRect(origin: .zero, size: SettingsLayout.size),
                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = SettingsText.windowTitle
        w.isReleasedWhenClosed = false
        w.tabbingMode = .disallowed
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        w.delegate = self
        let host = NSHostingView(rootView: SettingsView(
            model: model, onToggleLogin: onToggleLogin,
            onEqualizerMode: { [weak model] in model?.setEqualizerMode($0) },
            onSpotifyRow: { kind in Log.settings.info("settings spotify row=\(kind.rawValue, privacy: .public)") }))
        host.sizingOptions = []
        w.contentView = host
        w.setContentSize(SettingsLayout.size)
        Log.settings.info("settings window created")
        return w
    }
}
```
If Swift 6 rejects sending `app` into `assumeIsolated`, copy the pattern of `SpotifyObservers.swift` (extract what is needed inside the callback, then hop).

`AppDelegate.swift`: add
```swift
    private lazy var settingsWindow = SettingsWindowController(
        model: settings, onToggleLogin: { [weak self] in self?.toggleLoginFromWindow() })

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show(via: .reopen)
        return false
    }

    private func toggleLoginFromWindow() {
        let r = settings.toggleLaunchAtLogin()
        Log.settings.info("settings loginItem toggle from=\(String(describing: r.from), privacy: .public) action=\(String(describing: r.action), privacy: .public) ok=\(r.succeeded, privacy: .public) after=\(String(describing: r.after), privacy: .public)")
    }
```
and `_ = settingsWindow` right after the `settings.onQuit` assignment in `applicationDidFinishLaunching`.

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | grep -E 'warning:|error:|Build complete' | tail -3`
Expected: `Build complete!`, no warnings from `Sources/Shima`.

- [ ] **Step 3: Reopen, single window, close (AUTOMATED, announce: about 10 s, keys only)**

Run (note the frontmost app first):
```bash
SHIMA_FAKE_SPOTIFY=playing SHIMA_SETTINGS_DRY_OPEN=1 scripts/run.sh >/dev/null && sleep 2
pid="$(pgrep -nx Shima)"; front() { lsappinfo info -only bundleid "$(lsappinfo front)" | sed -E 's/.*="(.*)"/\1/'; }; orig="$(front)"
scripts/with-log.sh .build/s9.log -- bash -c "open dist/Shima.app; sleep 1.5; open dist/Shima.app; sleep 1; swift scripts/shima-windows.swift --settings $pid | head -2; swift scripts/drive.swift 'key cmd-w' >/dev/null; sleep 1; swift scripts/shima-windows.swift --settings $pid | head -1"
grep -E 'settings (window created|refresh|opened|closed|spotify row)' .build/s9.log | sed -E 's/^.*\] //'
echo "orig=$orig now=$(front)"; [[ "$(front)" == "$orig" ]] || open -b "$orig"
```
Expected: `settings windows: 1` with one `settings window x=… y=… w=440 h=…` line, then `settings windows: 0`; log: `settings window created` once; `settings refresh loginItem=notFound spotify=running eq=animated version="Version 0.0.1 (1)" signing="Signed ad hoc (no certificate)"` (twice); `settings spotify row=running`; `settings opened via reopen created=true active=true key=true`; `settings opened via reopen created=false active=true key=true`; `settings closed policy=accessory restored=<orig> active=…`; `orig` equals `now`.

- [ ] **Step 4: Decide the activation strategy (record it)**

Rules, using Step 3 now and Tasks 10 and 11 Step 3 later (gear and menu):
- Every entry logs `active=true key=true` → keep the cooperative path (`activationStrategy = cooperative`).
- Any entry logs `active=false` or `key=false` → replace `NSApp.activate()` in `show` with `NSApp.activate(ignoringOtherApps: true)` (deprecated in macOS 14: one build warning, accepted with a comment naming this rule) and re-run that entry's check (`activationStrategy = ignoringOtherApps`).
- Still not active or not key → add `NSApp.setActivationPolicy(.regular)` before activating in `show`, and `NSApp.setActivationPolicy(.accessory)` as the first line of `windowWillClose` (a Dock icon while the window is open, which the design's Risks section accepts) (`activationStrategy = regularWhileOpen`).
- If `restored=none` while Shima was active at close (focus not handed back), record it; `verify-settings.sh` restores the frontmost app itself.

Create `docs/superpowers/settings-acceptance.md` with `# Settings window acceptance record` and `## Decisions` (date, macOS version, `activationStrategy` and the log lines that decided it, whether close restored focus). Tasks 10 and 11 append their entry's result.

- [ ] **Step 5: Window controls (AUTOMATED, announce: about 10 s of pointer)**

Run:
```bash
open dist/Shima.app; sleep 1.5
read -r wx wy ww wh < <(swift scripts/shima-windows.swift --settings "$pid" | sed -nE 's/^settings window x=(-?[0-9]+) y=(-?[0-9]+) w=([0-9]+) h=([0-9]+)$/\1 \2 \3 \4/p')
top=$((wy + wh - 380))
scripts/with-log.sh .build/s9b.log -- swift scripts/drive.swift "click $((wx+365)) $((top+108)); sleep 500; click $((wx+185)) $((top+108)); sleep 500; fake denied; sleep 300; click $((wx+135)) $((top+240)); sleep 300; fake allowed; sleep 300; key cmd-w" >/dev/null
grep -E 'settings (eq|spotify row|open url|closed)' .build/s9b.log | sed -E 's/^.*\] //'
[[ "$(front)" == "$orig" ]] || open -b "$orig"
```
Expected: `settings eq mode=off saved`, `settings eq mode=animated saved`, `settings spotify row=permissionDenied`, `settings open url=x-apple.systempreferences:com.apple.preference.security?Privacy_Automation dryRun=true`, `settings spotify row=running`, `settings closed policy=accessory …`. If a click logs nothing, the window was not key (see Step 4) or the layout differs from `SettingsLayout` (check the `w=440` and the title-bar height `wh - 380`).

- [ ] **Step 6: Commit**

```bash
git add Sources/Shima/SettingsView.swift Sources/Shima/SettingsWindowController.swift Sources/Shima/AppDelegate.swift docs/superpowers/settings-acceptance.md
git commit -m "Add the Settings window, opened by re-launching Shima"
```

---

### Task 10: The gear on the open island (GLUE, sequential)

**Files:**
- Modify: `Sources/Shima/IslandView.swift`, `Sources/Shima/NowPlayingView.swift`, `Sources/Shima/IslandPanelController.swift`, `Sources/Shima/AppDelegate.swift`, `scripts/view-layout-check.swift`, `docs/superpowers/settings-acceptance.md`

**Interfaces:**
- Consumes: `NowPlayingLayout.settingsButton`, `titleRect`, `SettingsText.windowTitle`, `SettingsWindowController.show(via:)`.
- Produces:
  - `IslandView` gains `let onSettings: @MainActor () -> Void` (after `onCommand`) and a second `.overlay(alignment: .top)` with `SettingsGear(action: onSettings)`, `.opacity(state.mode == .expanded ? 1 : 0)`, `.allowsHitTesting(state.mode == .expanded)`. `struct SettingsGear: View` (in `IslandView.swift`) is an island-sized (`360 x 165`) `ZStack(alignment: .topLeading)` with one plain `Button` showing `gearshape.fill`, size 14, `Color.white.opacity(0.7)`, framed and positioned at `settingsButton`, `.contentShape(Circle())`, accessibility label `shima Settings`. Visible in every open-island content (track, not running, nothing playing, denied).
  - `NowPlayingView`: the title `Text` uses `.frame(width: NowPlayingLayout.titleRect.width, height: 18, alignment: .leading).position(x: NowPlayingLayout.titleRect.midX, y: NowPlayingLayout.titleRect.midY)`.
  - `IslandPanelController`: `var onSettings: (@MainActor () -> Void)?`; both `IslandView(...)` constructions pass `onSettings:` (`{}` in `init`, `{ [weak self] in self?.openSettings() }` in `place`); `openSettings()` logs `settings gear clicked active=<NSApp.isActive> key=<panel.isKeyWindow>` then calls `onSettings`.
  - `AppDelegate`: `islandController.onSettings = { [weak self] in self?.settingsWindow.show(via: .gear) }`.
  - `view-layout-check.swift`: passes `onSettings: {}`; checks the gear glyph in the expanded render and its absence in the live render.

- [ ] **Step 1: Add the gear check first**

In `scripts/view-layout-check.swift`: add `onSettings: {}` to the `IslandView(...)` call; add
```swift
    private static func isGear(_ color: NSColor) -> Bool {
        color.alphaComponent > 0.9 && color.redComponent > 0.45
            && abs(color.redComponent - color.greenComponent) < 0.05 && abs(color.greenComponent - color.blueComponent) < 0.05
    }
```
After `let live = render(host)`: `check(live.rows(in: 0..<245, ys: 0..<32, matching: isGear).isEmpty, "collapsed island must not show the gear")`. After `let expanded = render(host)`:
```swift
        let gearRect = NowPlayingLayout.settingsButton.offsetBy(dx: (396 - IslandLayout.expanded.width) / 2, dy: 0)
        let gear = expanded.rows(in: Int(gearRect.minX)..<Int(gearRect.maxX), ys: 30..<70, matching: isGear)
        check(!gear.isEmpty && gear.lowerBound >= Int(gearRect.minY) && gear.upperBound <= Int(gearRect.maxY),
              "gear glyph rows \(gear) outside \(gearRect)")
        print("gear at \(gearRect): glyph rows \(gear) PASS")
```
Run: `scripts/verify-view-layout.sh 2>&1 | tail -2`
Expected: a compile error `extra argument 'onSettings' in call` (the view does not have it yet).

- [ ] **Step 2: Implement** the Interfaces block.

- [ ] **Step 3: Verify**

1. `swift build 2>&1 | tail -1` → `Build complete!`.
2. `scripts/verify-view-layout.sh 2>&1 | tail -6` → the four PASS lines of Task 8 plus `gear at (340.0, 38.0, 24.0, 24.0): glyph rows 4x..<5x PASS` (rows inside 38..<62); the live line still `black 0..<32, artwork 6..<26, equalizer 9..<23` with bounds `(220.5, 9.0, 16.0, 14.0)`.
3. Gear opens the window (AUTOMATED, announce: about 10 s of pointer):
```bash
SHIMA_FAKE_SPOTIFY=playing SHIMA_SETTINGS_DRY_OPEN=1 scripts/run.sh >/dev/null && sleep 2
front() { lsappinfo info -only bundleid "$(lsappinfo front)" | sed -E 's/.*="(.*)"/\1/'; }; orig="$(front)"; pid="$(pgrep -nx Shima)"
scripts/with-log.sh .build/s10.log -- swift scripts/drive.swift "move 735 400; sleep 400; move 735 16; sleep 700; click 889.5 50; sleep 700; move 735 400; sleep 1200" >/dev/null
grep -E 'settings (gear clicked|opened)|hover dwelling -> expanded|app became active' .build/s10.log | sed -E 's/^.*\] //'
swift scripts/shima-windows.swift --settings "$pid" | head -1
swift scripts/drive.swift "key cmd-w" >/dev/null; sleep 1; [[ "$(front)" == "$orig" ]] || open -b "$orig"
```
Expected: `hover dwelling -> expanded`, `settings gear clicked active=false key=false`, `app became active` (the one intended activation, after the gear click), `settings opened via gear created=true active=true key=true`, `settings windows: 1`. Apply Task 9 Step 4's rules if `active` or `key` is false; append the result to `settings-acceptance.md`.
4. Island buttons still never activate (AUTOMATED, about 10 s): with the window closed and the frontmost app restored, `scripts/verify-focus.sh --clicks` → `PASS clicks: 3 commands, frontmost unchanged: <app>`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Shima/IslandView.swift Sources/Shima/NowPlayingView.swift Sources/Shima/IslandPanelController.swift Sources/Shima/AppDelegate.swift scripts/view-layout-check.swift docs/superpowers/settings-acceptance.md
git commit -m "Add a settings gear to the open island"
```

---

### Task 11: "Settings…" in the status menu (GLUE, sequential)

**Files:**
- Modify: `Sources/Shima/AppDelegate.swift`, `docs/superpowers/settings-acceptance.md`

**Interfaces:**
- Produces: the status menu becomes `Settings…` (key equivalent `,`, so Cmd-, while the menu is open), separator, `Launch at login`, separator, `Quit shima`; its action calls `settingsWindow.show(via: .menu)`. After `setUpStatusItem()`, one `DispatchQueue.main.async` logs `menu status item x=<x> y=<y> w=<w> h=<h>` in global top-left CG points from `statusItem?.button?.window?.frame` (`y = NSScreen.screens[0].frame.maxY - frame.maxY`), or `menu status item none` without a window. On this macOS the status item windows are owned by `Control Center` in the window list, so scripts cannot find Shima's item by owner; they read this line (plan note 11).

- [ ] **Step 1: Implement**

In `setUpStatusItem()`, before `menu.addItem(loginItemMenuItem)`:
```swift
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
```
After `statusItem = item`:
```swift
        DispatchQueue.main.async { [weak self] in self?.logStatusItemFrame() }
```
and add:
```swift
    @objc private func openSettingsFromMenu() { settingsWindow.show(via: .menu) }

    private func logStatusItemFrame() {
        guard let f = statusItem?.button?.window?.frame else { Log.menu.info("menu status item none"); return }
        let top = NSScreen.screens.first?.frame.maxY ?? f.maxY
        Log.menu.info("menu status item x=\(f.minX, format: .fixed(precision: 1), privacy: .public) y=\(top - f.maxY, format: .fixed(precision: 1), privacy: .public) w=\(f.width, format: .fixed(precision: 1), privacy: .public) h=\(f.height, format: .fixed(precision: 1), privacy: .public)")
    }
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -1`. Expected: `Build complete!`.

- [ ] **Step 3: Menu opens the window (AUTOMATED, announce: about 10 s of pointer)**

```bash
scripts/with-log.sh .build/s11a.log -- bash -c 'SHIMA_FAKE_SPOTIFY=playing SHIMA_SETTINGS_DRY_OPEN=1 scripts/run.sh >/dev/null; sleep 3'
grep -E 'menu status item' .build/s11a.log | sed -E 's/^.*\] //'
```
Expected: `menu status item x=… y=0.0 w=… h=…` (y about 0 and h about 33 when the item is in the built-in menu bar; a hidden item shows an off-screen x or `none`: then this step is SKIP, recorded, and entries 1 and 2 cover the full menu bar, design acceptance 7). With `sx` = x + w/2 rounded:
```bash
front() { lsappinfo info -only bundleid "$(lsappinfo front)" | sed -E 's/.*="(.*)"/\1/'; }; orig="$(front)"; pid="$(pgrep -nx Shima)"
swift scripts/drive.swift "click $sx 16; sleep 500" >/dev/null; swift scripts/shima-windows.swift --menus | grep 'owner=Shima'
# with mx my from that line:
scripts/with-log.sh .build/s11.log -- swift scripts/drive.swift "move $((mx+40)) $((my+16)); sleep 150; click $((mx+40)) $((my+16)); sleep 700" >/dev/null
grep -E 'settings opened' .build/s11.log | sed -E 's/^.*\] //'; swift scripts/shima-windows.swift --settings "$pid" | head -1
swift scripts/drive.swift "key cmd-w" >/dev/null; sleep 1; [[ "$(front)" == "$orig" ]] || open -b "$orig"
```
Expected: a `menu window owner=Shima x=… y=… w=… h=…` line (taller than M1's 34 pt: three items and two separators), `settings opened via menu created=true active=true key=true`, `settings windows: 1`. Apply Task 9 Step 4's rules; append to `settings-acceptance.md`. If no Shima menu opens, press Esc (`swift scripts/drive.swift "key esc"`) and record the click target.

- [ ] **Step 4: Commit**

```bash
git add Sources/Shima/AppDelegate.swift docs/superpowers/settings-acceptance.md
git commit -m "Add Settings… to the status menu and log the status item frame"
```

---

### Task 12: `scripts/verify-settings.sh` (SCRIPT, sequential)

**Files:**
- Create: `scripts/verify-settings.sh` (`chmod +x`)

**Interfaces:**
- Produces: `scripts/verify-settings.sh [--replace]` (dist build, fake playing, dry URL open) and `scripts/verify-settings.sh --login-item [--pause] [--replace]` (installed signed app, fake paused). Builds `.build/tools/drive` and `.build/tools/shima-windows` once with `swiftc` (fast steps), refuses to run while another Shima runs unless `--replace` (then stops `/Applications` or this checkout's dist instances by pid and does not restart them), keeps the Mac awake, captures one log stream, launches its own instance with `open --env`, finds its pid by executable path, kills only that pid, restores the frontmost app, and leaves the main-mode instance running (fake playing, window closed) for the M1 checks. Prints one `ok`/`FAIL`/`SKIP` line per check and `PASS settings` (exit 0) or `FAIL settings (<dir>)` (exit 1); exit 2 for preconditions.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Settings window checks (design 2026-11-22, acceptance 1-6). Fake mode only; never touches Spotify.
# Announce before running: about 60-90 s of synthetic pointer and key input.
#   scripts/verify-settings.sh [--replace]
#       dist/Shima.app: three entries and one window, close and focus, equalizer modes,
#       persistence across a relaunch, Spotify rows and the Automation URL, Quit
#   scripts/verify-settings.sh --login-item [--pause] [--replace]
#       /Applications/Shima.app (signed): Launch at login on, read back, off (ends OFF)
# Launches its own Shima and kills only that pid. --replace stops a Shima running from /Applications
# or this checkout's dist first (by pid) and does not restart it.
set -uo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
login=0; pause=0; replace=0
for a in "$@"; do
  case "$a" in
    --login-item) login=1 ;; --pause) pause=1 ;; --replace) replace=1 ;;
    *) echo "unknown argument: $a"; exit 2 ;;
  esac
done
if (( login )); then APP="/Applications/Shima.app"; else APP="$REPO/dist/Shima.app"; fi
BIN="$APP/Contents/MacOS/Shima"
[[ -x "$BIN" ]] || { echo "missing $BIN (scripts/bundle.sh, or scripts/install.sh for --login-item)"; exit 2; }
H=380                                   # SettingsLayout.size.height
N="735 16"; A="735 400"; GEAR="889.5 50" # NowPlayingLayout.settingsButtonCenter on this Mac
SEG_animated="185 108"; SEG_whenOpen="275 108"; SEG_off="365 108"   # SettingsLayoutTests pins these
LOGIN="28 50"; AUTOMATION="135 240"; QUIT="370 352"
dir="$(mktemp -d -t shima-settings)"; fail=0; pid=""; lp=""; cf=""; LAUNCH_MARK=0
wx=0; wy=0; ww=0; wh=0
tools="$REPO/.build/tools"; mkdir -p "$tools"
swiftc -O scripts/drive.swift -o "$tools/drive" >/dev/null 2>&1 || { echo "cannot build scripts/drive.swift"; exit 2; }
swiftc -O scripts/shima-windows.swift -o "$tools/shima-windows" >/dev/null 2>&1 || { echo "cannot build scripts/shima-windows.swift"; exit 2; }
d() { "$tools/drive" "$1" >/dev/null; }
front() { lsappinfo info -only bundleid "$(lsappinfo front)" | sed -E 's/.*="(.*)"/\1/'; }

others="$(pgrep -x Shima || true)"
if [[ -n "$others" ]]; then
  if (( replace )); then
    for p in $others; do
      cmd="$(ps -o command= -p "$p" || true)"
      case "$cmd" in
        /Applications/Shima.app/*|"$REPO/dist/Shima.app/"*) echo "stopping Shima pid $p ($cmd)"; kill "$p" ;;
        *) echo "Shima pid $p runs from elsewhere ($cmd); quit it first"; exit 2 ;;
      esac
    done
    for _ in $(seq 20); do pgrep -x Shima >/dev/null || break; sleep 0.2; done
  else
    echo "Shima is already running:"; for p in $others; do ps -o pid=,command= -p "$p"; done
    echo "quit it, or pass --replace to stop it by pid (it is not restarted)"; exit 2
  fi
fi
orig="$(front)"
cleanup() {
  [[ -n "$lp" ]] && { kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null; }
  [[ -n "$cf" ]] && kill "$cf" 2>/dev/null
  [[ -n "$orig" && "$orig" != local.shima && "$(front)" != "$orig" ]] && open -b "$orig"
}
trap cleanup EXIT
caffeinate -dimsu & cf=$!
/usr/bin/log stream --level debug --style compact --predicate 'subsystem == "local.shima"' > "$dir/all.log" 2>&1 & lp=$!
sleep 1.5

mark() { wc -l < "$dir/all.log" | tr -d ' '; }
since() { tail -n +"$(( $1 + 1 ))" "$dir/all.log"; }
has() { since "$1" | grep -qE -- "$2"; }
wait_for() { local i; for (( i = 0; i < ${3:-30}; i++ )); do has "$1" "$2" && return 0; sleep 0.1; done; return 1; }
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1${2:+ ($2)}"; fail=1; }
expect_log() { if wait_for "$2" "$3" "${4:-30}"; then ok "$1"; else bad "$1" "no '$3'"; fi; }
last_eq() { grep -oE 'eq (animating anims=[0-9]+|frozen anims=0)' "$dir/all.log" | tail -1 || true; }
expect_eq() { sleep 0.4; if [[ "$(last_eq)" == "$2" ]]; then ok "$1"; else bad "$1" "last '$(last_eq)', want '$2'"; fi; }
windows() { "$tools/shima-windows" --settings "$pid" | sed -nE 's/^settings windows: ([0-9]+)$/\1/p'; }
expect_windows() { local n; n="$(windows)"; if [[ "$n" == "$2" ]]; then ok "$1 ($n window)"; else bad "$1" "settings windows: $n, want $2"; fi; }
wrect() {
  local line; line="$("$tools/shima-windows" --settings "$pid" | sed -nE 's/^settings window x=(-?[0-9]+) y=(-?[0-9]+) w=([0-9]+) h=([0-9]+)$/\1 \2 \3 \4/p' | head -1)"
  [[ -n "$line" ]] || return 1; read -r wx wy ww wh <<< "$line"
}
wclick() { set -- $1; d "click $(( wx + $1 )) $(( wy + wh - H + $2 ))"; }
reopen() { local m; m="$(mark)"; open "$APP"; wait_for "$m" 'settings opened via reopen' 30; sleep 0.3; wrect; }
launch() { # KEY=VALUE...
  local m a=() kv p; m="$(mark)"
  for kv in "$@"; do a+=(--env "$kv"); done
  open "${a[@]}" "$APP"
  pid=""
  for _ in $(seq 50); do
    for p in $(pgrep -x Shima || true); do [[ "$(ps -o command= -p "$p" || true)" == "$BIN"* ]] && pid="$p"; done
    [[ -n "$pid" ]] && break; sleep 0.1
  done
  [[ -n "$pid" ]] || { echo "Shima did not start"; exit 2; }
  wait_for "$m" 'spotify mode fake' 50 || { echo "Shima pid $pid is not in fake mode; stopping it"; kill "$pid"; exit 2; }
  LAUNCH_MARK="$m"
}
stop_own() { [[ -n "$pid" ]] || return 0; kill "$pid" 2>/dev/null; for _ in $(seq 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done; }
locked() { swift - <<'SW'
import CoreGraphics
let d = CGSessionCopyCurrentDictionary() as? [String: Any]
let v = d?["CGSSessionScreenIsLocked"]
print((v as? Bool) == true || (v as? Int) == 1 ? 1 : 0)
SW
}

if (( login )); then
  codesign -dvv "$APP" 2>&1 | grep -q '^Authority=Apple Development' \
    || { echo "$APP is not signed with the Apple Development identity (SHIMA_SIGN_ID=... scripts/install.sh)"; exit 2; }
  launch SHIMA_FAKE_SPOTIFY=paused SHIMA_SETTINGS_DRY_OPEN=1
  m="$(mark)"; reopen || bad "L1 window bounds"
  before="$(since "$m" | grep -oE 'settings refresh loginItem=[A-Za-z]+' | tail -1 | sed 's/.*=//')"
  echo "     Launch at login before: ${before:-unknown}"
  [[ "$before" != enabled ]] || { echo "Launch at login is already ON; turn it off in the window, then re-run"; exit 2; }
  m="$(mark)"; wclick "$LOGIN"
  expect_log "L2 register" "$m" "settings loginItem toggle from=$before action=register ok=true after=enabled"
  if (( pause )); then
    read -r -p "Launch at login is ON: check System Settings > General > Login Items & Extensions, then press Return " _
  fi
  m="$(mark)"; reopen
  expect_log "L3 status reads back enabled" "$m" 'settings refresh loginItem=enabled'
  m="$(mark)"; wclick "$LOGIN"
  expect_log "L4 unregister" "$m" 'settings loginItem toggle from=enabled action=unregister ok=true after=notRegistered'
  m="$(mark)"; reopen
  expect_log "L5 ends OFF" "$m" 'settings refresh loginItem=notRegistered'
  d "key cmd-w"; sleep 0.5
  stop_own
  echo "stopped the test instance (pid $pid); /Applications/Shima.app is not running"
  (( fail == 0 )) && { echo "PASS login item"; exit 0; } || { echo "FAIL login item ($dir)"; exit 1; }
fi

launch SHIMA_FAKE_SPOTIFY=playing SHIMA_SETTINGS_DRY_OPEN=1
echo "Shima pid $pid (fake playing); driving pointer and keys for about a minute"
echo "     $(since "$LAUNCH_MARK" | grep -oE 'settings eq mode=[A-Za-z]+ loaded' | tail -1)"

# A. Reopen (entry 1) and one window
m="$(mark)"; open "$APP"
expect_log "A1 reopen opens the window, active and key" "$m" 'settings opened via reopen created=true active=true key=true'
expect_windows "A1 one window" 1
wrect && [[ "$ww" == 440 ]] && ok "A1 window width 440" || bad "A1 window bounds" "x=$wx y=$wy w=$ww h=$wh"
if ! since "$LAUNCH_MARK" | grep -q 'settings eq mode=animated loaded'; then wclick "$SEG_animated"; sleep 0.5; fi
m="$(mark)"; open "$APP"
expect_log "A2 second reopen reuses it" "$m" 'settings opened via reopen created=false'
expect_windows "A2 still one window" 1

# B. Close: accessory, focus back
m="$(mark)"; d "key cmd-w"
expect_log "B1 closed, policy accessory" "$m" 'settings closed policy=accessory'
sleep 0.3; expect_windows "B1 no window" 0
now="$(front)"; if [[ "$now" == "$orig" ]]; then ok "B2 focus back to $orig"; else bad "B2 focus back" "frontmost $now, want $orig"; open -b "$orig"; fi
echo "     lsappinfo: $(lsappinfo info -only ApplicationType "$(lsappinfo find pid="$pid")" 2>/dev/null)"

# C. Gear (entry 2)
m="$(mark)"; d "move $A; sleep 400; move $N; sleep 700; click $GEAR; sleep 700"
expect_log "C1 gear click on the non-key panel" "$m" 'settings gear clicked active=false key=false'
expect_log "C2 gear opens the same window, active and key" "$m" 'settings opened via gear created=false active=true key=true'
d "move $A; sleep 1200"
expect_windows "C2 one window" 1
m="$(mark)"; d "move $N; sleep 700; click $GEAR; sleep 700; move $A; sleep 1200"
expect_log "C3 second gear click reuses it" "$m" 'settings opened via gear created=false'
expect_windows "C3 still one window" 1

# D. Status menu (entry 3), when the item is visible
item="$(grep -oE 'menu status item x=-?[0-9.]+ y=-?[0-9.]+ w=[0-9.]+' "$dir/all.log" | tail -1)"
sx="${SHIMA_STATUS_ITEM_X:-}"
if [[ -z "$sx" && -n "$item" ]]; then
  sx="$(echo "$item" | awk '{ for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] } } END { if (v["x"] >= 0 && v["x"] < 1470) printf "%.0f", v["x"] + v["w"] / 2 }')"
fi
if [[ -z "$sx" ]]; then
  echo "SKIP D status item not on the built-in menu bar (${item:-no status item line}); entries 1 and 2 cover a full menu bar"
else
  d "click $sx 16; sleep 500"
  menu="$("$tools/shima-windows" --menus | sed -nE 's/^menu window owner=Shima x=(-?[0-9]+) y=(-?[0-9]+) w=([0-9]+) h=([0-9]+)$/\1 \2 \3 \4/p' | head -1)"
  if [[ -z "$menu" ]]; then
    d "key esc"; echo "SKIP D no Shima menu after a click at x=$sx (item hidden or moved; set SHIMA_STATUS_ITEM_X)"
  else
    read -r mx my mw mh <<< "$menu"
    m="$(mark)"; d "move $(( mx + 40 )) $(( my + 16 )); sleep 150; click $(( mx + 40 )) $(( my + 16 )); sleep 700"
    expect_log "D1 status menu Settings… opens the same window" "$m" 'settings opened via menu created=false'
    expect_windows "D1 one window" 1
  fi
fi

# E. Equalizer modes (live, collapsed, fake playing)
if [[ "$(locked)" == 1 ]]; then bad "E screen unlocked" "the screen is locked; equalizer checks are invalid"; fi
reopen || bad "E window bounds"
expect_eq "E0 live wings animate (animated)" 'eq animating anims=4'
m="$(mark)"; wclick "$SEG_off"; expect_log "E1 mode off saved" "$m" 'settings eq mode=off saved'
expect_eq "E1 live wings frozen" 'eq frozen anims=0'
m="$(mark)"; wclick "$SEG_whenOpen"; expect_log "E2 mode whenOpen saved" "$m" 'settings eq mode=whenOpen saved'
expect_eq "E2 collapsed stays frozen" 'eq frozen anims=0'
d "move $N; sleep 900"; expect_eq "E3 open island animates" 'eq animating anims=4'
d "move $A; sleep 1500"; expect_eq "E4 collapsed again, frozen" 'eq frozen anims=0'
reopen
m="$(mark)"; wclick "$SEG_animated"; expect_log "E5 mode animated saved" "$m" 'settings eq mode=animated saved'
expect_eq "E5 live wings animate" 'eq animating anims=4'

# F. Spotify rows and the Automation button
m="$(mark)"; d "fake quit"; expect_log "F1 row notRunning" "$m" 'settings spotify row=notRunning'
m="$(mark)"; d "fake launch"; expect_log "F2 row running" "$m" 'settings spotify row=running'
m="$(mark)"; d "fake denied"; expect_log "F3 row permissionDenied" "$m" 'settings spotify row=permissionDenied'
reopen
m="$(mark)"; wclick "$AUTOMATION"
expect_log "F4 button logs the Automation URL (dry run)" "$m" 'settings open url=x-apple\.systempreferences:com\.apple\.preference\.security\?Privacy_Automation dryRun=true'
m="$(mark)"; d "fake allowed"; expect_log "F5 row running again" "$m" 'settings spotify row=running'
d "fake playing"; sleep 0.5

# G. Persistence across a relaunch, and Quit
reopen
m="$(mark)"; wclick "$SEG_off"; expect_log "G1 mode off saved" "$m" 'settings eq mode=off saved'
old="$pid"; m="$(mark)"; wclick "$QUIT"
expect_log "G2 quit logged" "$m" 'settings quit'
gone=0; for _ in $(seq 30); do kill -0 "$old" 2>/dev/null || { gone=1; break; }; sleep 0.1; done
if (( gone )); then ok "G2 Quit ends the process"; else bad "G2 Quit ends the process" "pid $old still running"; kill "$old"; fi
launch SHIMA_FAKE_SPOTIFY=playing SHIMA_SETTINGS_DRY_OPEN=1
expect_log "G3 mode off loaded after relaunch" "$LAUNCH_MARK" 'settings eq mode=off loaded'
expect_log "G3 island live" "$LAUNCH_MARK" 'spotify live true'
sleep 1.5
if has "$LAUNCH_MARK" 'eq animating'; then bad "G4 wings stay still with mode off" "eq animating after relaunch"; else ok "G4 wings stay still with mode off"; fi
m="$(mark)"; open "$APP"
expect_log "G5 window after relaunch" "$m" 'settings opened via reopen created=true'
sleep 0.3; wrect || bad "G window bounds"
m="$(mark)"; wclick "$SEG_animated"; expect_log "G6 mode animated saved" "$m" 'settings eq mode=animated saved'
expect_eq "G6 wings animate" 'eq animating anims=4'
stored="$(defaults read local.shima equalizerMode 2>/dev/null || echo none)"
if [[ "$stored" == animated ]]; then ok "G7 stored equalizerMode=animated"; else bad "G7 stored equalizerMode" "$stored"; fi
m="$(mark)"; d "key cmd-w"; expect_log "G8 closed, policy accessory" "$m" 'settings closed policy=accessory'

[[ "$(front)" == "$orig" ]] || open -b "$orig"
echo "Shima pid $pid left running (fake playing, Settings closed) for the M1 checks; stop it with: kill $pid"
(( fail == 0 )) && echo "PASS settings" || { echo "FAIL settings ($dir)"; exit 1; }
```

- [ ] **Step 2: Syntax check**

Run: `bash -n scripts/verify-settings.sh && echo syntax ok`. Expected: `syntax ok`. (macOS `/bin/bash` is 3.2: no associative arrays or `mapfile` in the script.)

- [ ] **Step 3: Run (AUTOMATED; announce "about 90 s of pointer and keys, please keep hands off")**

Run (Terminal or the user's usual app frontmost): `scripts/bundle.sh >/dev/null && scripts/verify-settings.sh` (add `--replace` if the installed Shima runs; see call 2).
Expected: every line `ok` (D may be `SKIP` with its reason), then `PASS settings`. Record failures with the `$dir/all.log` path; fix the script or the code, re-run.

- [ ] **Step 4: Commit**

```bash
git add scripts/verify-settings.sh
git commit -m "Add verify-settings.sh: entries, one window, focus, equalizer modes, Spotify rows, Quit, login item"
```

---

### Task 13: Signed install, Launch at login, and the real Automation button (HUMAN + AUTOMATED)

Design acceptance 2 and the non-dry half of 4. Needs the signed copy in `/Applications` (SMAppService works there; `notFound` before the first registration is normal).

**Files:**
- Modify: `docs/superpowers/settings-acceptance.md`

- [ ] **Step 1: Install signed (AUTOMATED, HUMAN if a keychain prompt appears)**

Run: `SHIMA_SIGN_ID='Apple Development: jpatrickzephyr@gmail.com (<cert-id>)' scripts/install.sh | tail -3`
Expected: `Installed /Applications/Shima.app` and a `designated =>` line with `certificate leaf[subject.CN] = "Apple Development: …"` (no `cdhash`). `install.sh` stops a running `/Applications` or dist Shima by pid. If "codesign wants to access key" appears, the user chooses.

- [ ] **Step 2: Launch at login (AUTOMATED with a HUMAN pause, about 30 s)**

Run: `scripts/verify-settings.sh --login-item --pause`
At the pause the user opens System Settings › General › Login Items & Extensions and confirms Shima is listed under "Open at Login", then presses Return. macOS may show a "Login item added" notification: expected.
Expected: `ok L2 register`, `ok L3 status reads back enabled`, `ok L4 unregister`, `ok L5 ends OFF`, `PASS login item`. If L2 shows `after=requiresApproval`, record it, have the user approve in System Settings, then turn it off again from the window.
Optional, read-only: `sfltool dumpbtm 2>&1 | grep -B2 -A6 local.shima`. If it asks for an admin password or prints a permission error, skip it; never run it with `sudo` without the user.

- [ ] **Step 3: Real Automation button and the signing text (HUMAN, about 20 s)**

```bash
scripts/with-log.sh .build/s13.log -- bash -c 'open --env SHIMA_FAKE_SPOTIFY=paused /Applications/Shima.app; sleep 3; open /Applications/Shima.app; sleep 2'
grep -E 'settings refresh' .build/s13.log | tail -1 | sed -E 's/^.*\] //'
```
Expected: `… version="Version 0.0.1 (1)" signing="Apple Development certificate expires 2027-03-26"`. Then the user clicks "Open Automation Settings…" in the window: System Settings opens at Privacy & Security › Automation (user confirms the pane), the log shows `settings open url=… dryRun=false`. The user closes System Settings and the Settings window. Stop the test instance by pid (`ps -o command=` shows `/Applications/Shima.app/…`); the user reopens the installed app in real mode when they want it.

- [ ] **Step 4: Record and commit**

Append `## Launch at login and Automation button` to `docs/superpowers/settings-acceptance.md` (date, output lines, the System Settings observations, whether `sfltool` ran).
```bash
git add docs/superpowers/settings-acceptance.md
git commit -m "Record the Launch at login and Automation button checks"
```

---

### Task 14: Acceptance run, M1 regressions, final install (ACCEPTANCE)

**Files:**
- Modify: `docs/superpowers/settings-acceptance.md`

- [ ] **Step 1: Fresh build and tests**

Run: `swift test 2>&1 | tail -1 && scripts/bundle.sh | tail -1 && pgrep -lx Spotify`
Expected: starts with `✔ Test run with 270 tests in 21 suites passed`; `Built dist/Shima.app`; note the Spotify pid (it must be the same at the end).

- [ ] **Step 2: Announced batches (each at most about 2 minutes)**

1. Batch 1, hands off about 90 s: `scripts/verify-settings.sh` → `PASS settings` (leaves a fake-playing dist instance running, window closed).
2. Batch 2, hands off about 20 s: `scripts/verify-focus.sh --clicks` → `PASS clicks: 3 commands, frontmost unchanged: <app>`. Then `kill <pid printed by verify-settings>`.
3. Batch 3, hands off about 60 s: `SHIMA_FAKE_SPOTIFY=paused scripts/run.sh && sleep 3 && scripts/verify-live-hover.sh` → `PASS live hover`.
4. CPU, not hands off (keep the pointer away from the notch, use the Mac normally): with the paused instance from batch 3, open and close the window first, then measure:
```bash
front() { lsappinfo info -only bundleid "$(lsappinfo front)" | sed -E 's/.*="(.*)"/\1/'; }; orig="$(front)"
open dist/Shima.app && sleep 1.5 && swift scripts/drive.swift "key cmd-w" >/dev/null && sleep 1 && { [[ "$(front)" == "$orig" ]] || open -b "$orig"; }
scripts/verify-idle.sh
```
Expected: static check `ok`, `cpu seconds used in 60 s: ≤ 0.030`, `sample: no timer callbacks`, `PASS idle`.
5. No pointer: `scripts/verify-view-layout.sh` → the PASS lines including `gear at …`; `scripts/verify-alignment.sh` → `PASS idle frame matches notch within 1pt` (paused instance).
6. Stop the paused instance by pid. `pgrep -lx Spotify` → same pid as Step 1.

- [ ] **Step 3: Record**

Complete `docs/superpowers/settings-acceptance.md`: date, macOS, Swift, build commit, decisions (activation strategy, focus hand-back, gear position, equalizer in the open island), how evidence was gathered (fake mode, CGEvent, log, window list, offscreen render; no screenshots), and:

| # | Criterion (design) | Evidence | Kind |
|---|---|---|---|
| 1 | Each entry opens the same single window | `verify-settings.sh` A1, A2, C2, C3, D1 (or SKIP with reason) | AUTOMATED |
| 2 | Launch at login toggles and matches System Settings, ends OFF | Task 13 Step 2 (L2-L5, System Settings glance, `sfltool` if it ran) | AUTOMATED + HUMAN |
| 3 | Quit ends the process | `verify-settings.sh` G2 | AUTOMATED |
| 4 | Spotify rows in fake mode, URL logged | F1-F5; Task 13 Step 3 (real open) | AUTOMATED + HUMAN |
| 5 | Equalizer mode persists and changes the wings | E0-E5, G1-G7 | AUTOMATED |
| 6 | Back to `.accessory`; island as before | B1, B2, G8; batches 2-5 | AUTOMATED |
| 7 | Works with the menu bar full | Entries 1 and 2 (A, C) pass independently of the status item; D's result noted | AUTOMATED |
| - | Version and certificate expiry shown | Task 9 Step 3 (dist: ad hoc), Task 13 Step 3 (signed: expires 2027-03-26) | AUTOMATED |

Every failure or partial gets a follow-up line.

- [ ] **Step 4: Final install (AUTOMATED; HUMAN reopen)**

If any commit landed after Task 13 Step 1: `SHIMA_SIGN_ID='Apple Development: jpatrickzephyr@gmail.com (<cert-id>)' scripts/install.sh | tail -2` → `Installed /Applications/Shima.app`. The user opens `/Applications/Shima.app` (real mode) when they want it back; the controller does not start real mode.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/settings-acceptance.md
git commit -m "Record Settings window acceptance results"
```

---

## Plan notes / deviations

Places where the plan makes a call, or where the design is ambiguous, inconsistent or slightly wrong. None was settled silently.

1. **`whenOpen` needs an equalizer in the open island (call 1).** In M1 the equalizer exists only in the wings, which are hidden (opacity 0) while the island is open, so "animate only while the island is open" would animate invisible bars and look the same as `off`. The plan keeps the wing's equalizer visible at its spot right of the notch while the open island shows a track (still bars when paused or `off`). `animated` then also animates while open (bars bounce whenever music plays, as the design says), `whenOpen` only while open. This changes the M1 open-island look and M1 Review Focus 6 ("nothing animates while expanded"); the open-island animation falls under section 2's open-and-playing exception, like `TimelineView`. Alternative: drop `whenOpen` and offer `animated`/`off` only.
2. **Gear position.** "Top-right of the expanded island" literally is the top strip right of the notch, but that strip sits over the menu bar's status items, which on this macOS are `Control Center` windows at the island's level 25 (window list, 2026-11-22); which window gets a click there is unknown. The gear sits at island `(322, 38, 24, 24)`, just below the 33 pt menu bar, and the title narrows from 230 to 200 pt. Still top-right and outside the now-playing column's text.
3. **UserDefaults suite.** The design's suite `local.shima` equals the bundle id; `UserDefaults(suiteName:)` with the own bundle id logs a warning and is documented as invalid. In the bundle the plan uses `UserDefaults.standard`, which is the same `local.shima` domain and plist; unbundled it uses the suite. The dist, Codex and installed builds share this domain, so test runs change the installed app's preference; `verify-settings.sh` ends with `animated`, and no step uses `defaults write`.
4. **"Automation permission granted" is not knowable from `SpotifyAvailability`.** `.running` means no `-1743` was seen since Spotify launched (it could also be "not asked yet"). The row says "Automation: allowed, or not asked yet." `AEDeterminePermissionToAutomateTarget` could tell, but it is a new interaction with Spotify and outside the design ("derived from AppState").
5. **Activation policy vs the anti-goal.** The anti-goal forbids a Dock icon; the Risks section accepts one while the window is open. The plan tries the cooperative macOS 14 `NSApp.activate()` with `.accessory` throughout (no Dock icon), and falls back to `activate(ignoringOtherApps:)`, then to `.regular` while open, only if the logs show the window not active or not key (Task 9 Step 4).
6. **Focus after close (not in the design).** Closing the window yields activation back to the app that was active before (`NSApp.yieldActivation(to:)` and `activate(from:options:)`, macOS 14), tracked with a workspace `didDeactivateApplication` observer (event-driven, not a timer, about one callback per app switch). Without it an accessory app would stay active with no window.
7. **Keyboard.** An accessory app has no main menu, so Cmd-W does not close windows by itself; `SettingsWindow` handles Cmd-W. The design's "Settings… (Cmd-,)" works while the status menu is open (status menus have no global shortcut).
8. **Fixed layout.** The window uses fixed rects (`SettingsLayout`) and three plain buttons instead of a `Form` and a segmented `Picker`, so scripts can click by coordinates without Accessibility queries or screenshots. Slightly less native-looking; the user can ask for a `Form` later at the cost of AX-based scripts.
9. **New fake and test hooks.** Fake commands `denied`, `allowed` and `eq-mode-<mode>` (fake mode only), and `SHIMA_SETTINGS_DRY_OPEN=1` (log the URL, do not open System Settings). The design names only "fake denied" as an example.
10. **Approach name.** The design calls approach 1 a "SwiftUI `Window`" but describes an `NSWindowController`-style window; an `NSApplication`-delegate app without a SwiftUI `App` cannot use a `Window` scene, so the plan uses an `NSWindow` with an `NSHostingView` and a plain controller object.
11. **Status item lookup.** On this macOS the status item windows are owned by `Control Center`, not by the app, so scripts cannot find Shima's capsule by owner. Shima logs its item's frame at launch (Task 11); a hidden item (full menu bar) makes check D a SKIP, which design acceptance 7 allows.
12. **`run.sh` used `pkill -x Shima`** (kills Codex's and the installed instance). Task 6 changes it to kill only this checkout's dist pid.
13. **`verify-view-layout.sh` default.** Its non-`--now-playing` branch was stale since M1 (parked minor); Task 8 makes the now-playing checks the default and keeps accepting the flag.
14. **Signing details.** Read with the Security framework on the first refresh (not at launch), `SecCertificateCopyNotValidAfterDate` on macOS 15+ (this Mac runs 26) with a `SecCertificateCopyValues` fallback for 14. The window shows "Apple Development", not the email in the certificate name. "see docs" only when the date is unreadable.
15. **Launch at login is tested only on the signed `/Applications` copy** (registering `dist/` would add a login item pointing into the repo). `sfltool dumpbtm` may need admin rights: then the check is the status readback plus a System Settings glance.
16. **Shared login-item state.** Menu and window now share `SettingsModel`, so a failed registration shows "unavailable" in both; the menu's log lines keep their wording.
17. **One-shot `DispatchQueue.main.async`** is used to log `settings opened … active= key=` after activation settles, and the status item frame after layout. Neither repeats.
18. **External display.** A second screen was attached on 2026-11-22; `window.center()` may put the Settings window there. Scripts read the window's bounds, so nothing depends on which screen.

## Calls for the user

1. **Show the equalizer in the open island (note 1)?** Recommendation: yes; it is what makes `whenOpen` mean something, and it keeps the bars in one place.
2. **May test scripts stop the installed `/Applications/Shima.app` by pid during runs (`--replace`) and leave it stopped until you reopen it?** Two Shima instances would put two islands on one notch and mix their logs. Recommendation: yes; scripts never start real mode themselves.
