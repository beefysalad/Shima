# Device pop-ups and peek banner Implementation Plan

> **For agentic workers (Codex):** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax. Read `CLAUDE.md` first (project rules and gotchas). Work in a worktree `.worktrees/devices` on branch `devices` (`git worktree add .worktrees/devices -b devices`). Tasks 2-4 may start before the calendar branch merges; rebase on `main` before 5a (both branches touch `AppState.swift`, `IslandView.swift`, `IslandPanelController.swift`, `AppDelegate.swift`, `scripts/bundle.sh`). Task labels: **PURE** (ShimaCore), **GLUE** (Shima app), **SCRIPT**, **HUMAN/CLAUDE** (not for Codex; skip and report when you reach one).

**Goal:** When a Bluetooth device connects, the collapsed island drops a 3-second "Connected, <name>" banner (the peek), built on a reusable peek mechanism in the hover state machine.

**Architecture:** `IslandMode.peek` + `HoverPhase.peeking` in the existing hover machine own panel size, hot region and generations (no second owner). A pure `DevicePeekPolicy` decides what to show; a `DeviceClient` protocol (IOBluetooth in the app, fake in tests) reports connections; `DeviceService` glues them to `IslandPanelController`.

**Tech Stack:** Swift 6 toolchain, SwiftPM only, Swift Testing (no XCTest), IOBluetooth (app target only), SwiftUI. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-11-23-device-popups-design.md`. Mirror these existing files: `Sources/ShimaCore/{HoverMachine,HoverController,IslandLayout}.swift`, `Tests/ShimaCoreTests/{HoverMachineTests,HoverControllerTests,IslandLayoutTests,ManualScheduler}.swift`, `Sources/Shima/IslandPanelController.swift`, `Sources/ShimaCore/{SettingsStore,SettingsModel}.swift`, `Sources/Shima/SpotifyService.swift` (fake-mode notification pattern).

## Ownership (decided 2026-11-23)

Codex does logic, wiring and scripts. **Claude does every view, layout constant, animation feel, the Settings row, and the visual comparison against the mockup** (the user does not trust Codex to reproduce the mockup). Codex: do only tasks labelled Codex; at a Claude task, stop, report, and wait. Mockup approved by the user 2026-11-23.

| Task | Owner |
|---|---|
| 0 Mockup and layout table | Claude (done, approved) |
| 1 Bluetooth spike | **Claude, done 2026-11-23** |
| 2 Peek geometry | Codex |
| 3 Hover machine peek phase | Codex (Claude reviews closely) |
| 4 Device types, policy, client protocol, setting | Codex |
| 5a Panel controller peek effects | Codex |
| 5b Peek UI: `PeekLayout`, `PeekContent`, `IslandView` overlay, animation feel | **Claude** |
| 6a `DeviceService`, IOBluetooth client, wiring, fake mode | Codex (needs Task 1) |
| 6b "Device pop-ups" row in the Settings window | **Claude** |
| 7a `fake-device` command, `verify-peek.sh`, regression runs | Codex |
| 7b Offscreen renders and mockup comparison | **Claude** |
| 8 Review and acceptance | Claude and the user |

Order: 2, 3 and 4 can run in parallel (separate files); 5a after 2-4; Claude does 5b after 5a; Task 1 any time before 6a; then 6a/6b, 7a/7b, 8. Tasks 2-4 may start in their own worktree before the calendar branch merges (small `AppState` conflict to resolve on rebase).

## Global Constraints

- `ShimaCore` must not import AppKit or IOBluetooth. IOBluetooth lives in `Sources/Shima/`.
- SwiftPM only; no third-party dependencies.
- No polling and no timers while idle. The only timer is the hover controller's peek timer, alive only while a peek is on screen. Detection is notification-driven.
- The island panel never steals focus (a peek must not activate shima or take key status). Hover must keep working during a peek.
- The collapsed idle size and the expanded 400 x 200 island are unchanged. The panel frame is resized only by the hover machine's effects, never by a view.
- Nothing may enlarge the island root `ZStack`; the peek content is an overlay with explicit frames.
- The real UI must match `mockup/index.html` (Task 0 extends it first). Peek island (real scale, see the spec's Layout table): 340 x 76, bottom radius 22, ear radius 10. The mockup's 460 x 84 is mockup scale, not points.
- Commit messages: plain, no attribution trailers. Stage explicit paths, never `git add -A`. No signing identifiers, `.build`, `dist` in commits. Never use real Bluetooth in scripts: fake mode only. Kill the app by pid, never `pkill -x Shima`.
- The terminal has no Screen Recording permission: verify with logs, window list, CGEvent input and offscreen renders.
- Info.plist key `NSBluetoothAlwaysUsageDescription` is mandatory (spike S1: without it TCC kills the process at the first IOBluetooth call). Suggested text: "shima shows a short banner when a Bluetooth device such as AirPods or a keyboard connects."

## Review Focus

1. A peek request while the pointer already hovers the notch (phase not collapsed) must be dropped, not shown under the cursor (Task 3: `peekIgnoredUnlessCollapsed`).
2. Hover entering the banner during a peek must open the full island exactly once and cancel the peek timer; a late `peekElapsed` must not collapse it (Task 3: `hoverDuringPeekExpandsAndStaleTimerIsIgnored`).
3. A collapse completion from a peek arriving after a re-hover must be ignored (generation numbers) (Task 3: `peekCollapseCompletionAfterRehover`).
4. A second device event during a peek replaces the content and restarts the timer without resizing the panel (Task 3: `secondPeekRestartsTimer`; Task 5: `secondPeekReplacesContent`).
5. Device names that are empty, very long, or contain only whitespace; battery values outside 0...100 (Task 4: `displayNameFallbackAndTruncation`, `batteryOutOfRangeIsHidden`).

---

### Task 0: Mockup (Claude, done, approved by the user 2026-11-23)

`mockup/index.html` now has the device peek variants and the Settings row, and the spec ends with the "Layout table" (real-scale peek 340 x 76, content rects, glyph source). Approved by the user 2026-11-23; the numbers are in the spec's Layout table (used by Claude in Tasks 5b and 6b).

### Task 1: Spike S1, Bluetooth notifications (Claude, DONE 2026-11-23; results in `docs/superpowers/spikes/2026-11-23-device-spikes.md`)

Claude, with the user connecting and disconnecting the Keychron K3 and AirPods 4, answers the questions in the spec's "Spike S1" section and writes `docs/superpowers/spikes/2026-11-23-device-spikes.md` containing: the chosen detection path (IOBluetooth connect notifications or the IOKit matching fallback), whether `NSBluetoothAlwaysUsageDescription` is needed, the exact API calls and property names that yield name, address, class of device and (if any) battery, and a battery yes/no per device. Codex's Task 6a reads this file; if it is missing, stop and report. Tasks 2-5 do not depend on it and can run first.

### Task 2: Peek geometry (PURE, Codex)

**Files:**
- Modify: `Sources/ShimaCore/IslandLayout.swift`, `Sources/ShimaCore/EqualizerMode.swift` (switches over `IslandMode`), `Sources/ShimaCore/CameraModel.swift` (verify only: `.peek` is not visible for the camera)
- Test: `Tests/ShimaCoreTests/IslandLayoutTests.swift`, `Tests/ShimaCoreTests/EqualizerModeTests.swift`

**Interfaces:**
- Produces:
  - `IslandMode.peek`
  - `HotRegion.peek`
  - `IslandLayout.peek = IslandShapeMetrics(width: 340, height: 76, bottomRadius: 22, earRadius: 10)`
  - `IslandLayout.metrics(for: .peek, notch:, live:)` returns `IslandLayout.peek`
  - `IslandLayout.peekPanelFrame(notch: CGRect) -> CGRect`: width `340 + 2*10 + 2*hoverMargin` (376), height `76 + hoverMargin` (84), centred on `notch.midX`, top edge at `notch.maxY` (same construction as the expanded `panelFrame`)
  - `IslandLayout.hotRect(.peek, notch:, live:, panelFrame:)` is the whole panel in local coordinates, like `.expanded`.

- [ ] **Step 1: Write failing tests** with the same `notch` fixture the existing tests use: `peekPanelFrameIsCentredAndTopAligned` (width 376, height 84, `midX == notch.midX`, `maxY == notch.maxY`); `peekHotRectIsWholePanel`; `peekMetricsAreMockupValues`; `peekKeepsWingsLikeCollapsed` (`EqualizerPolicy`'s visible/animating functions treat `.peek` exactly like `.collapsed`: `isVisible(island: .peek, live: true, content: .track) == true` and `isVisible(island: .peek, live: false, ...) == false`; the mockup keeps the collapsed wings visible during a peek, so the real island does too; `isAnimating(.whenOpen, island: .peek, ...) == false`). Keep all existing layout tests unchanged.
- [ ] **Step 2: Run** `swift test --filter "IslandLayoutTests|EqualizerModeTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** the above; fix every `switch` over `IslandMode`/`HotRegion` the compiler flags (`swift build` lists them).
- [ ] **Step 4: Run** `swift build && swift test`. Expected: pass, no warnings.
- [ ] **Step 5: Commit** explicit paths, message `Peek: island mode and geometry`.

### Task 3: Hover machine peek phase (PURE, Codex)

**Files:**
- Modify: `Sources/ShimaCore/HoverMachine.swift`, `Sources/ShimaCore/HoverController.swift`
- Test: `Tests/ShimaCoreTests/HoverMachineTests.swift`, `Tests/ShimaCoreTests/HoverControllerTests.swift`

**Interfaces:**
- Consumes: `HotRegion.peek` (Task 2).
- Produces:
  - `HoverPhase.peeking`; `HoverTimer.peek`; `HoverInput.peekRequested`, `HoverInput.peekElapsed`; `HoverEffect.growPanelForPeek`, `HoverEffect.animatePeekIn`.
  - `HoverController.peek(duration: Duration) -> Bool` (`@discardableResult`): returns `true` when the request is honoured (phase was `.collapsed` or `.peeking`), `false` when dropped. Stores `duration` for the `.peek` timer; `HoverController` maps `HoverTimer.peek` to it.

**Machine rules** (everything not listed keeps today's behaviour):
- `(.collapsed, .peekRequested)` -> phase `.peeking`, panel marked large and peek-sized, effects exactly `[.growPanelForPeek, .setHotRegion(.peek), .animatePeekIn, .startTimer(.peek)]`.
- `(.peeking, .peekRequested)` -> `[.startTimer(.peek)]`, phase unchanged.
- `(.peeking, .peekElapsed)` -> `generation += 1`, phase `.collapsing`, effects `[.setHotRegion(.idle), .animateCollapse(generation: generation)]`; the existing `(.collapsing, .collapseFinished)` then yields `.shrinkPanel`.
- `(.peeking, .pointer(inside: true))` -> phase `.dwelling`, effects `[.startTimer(.dwell)]` (the controller replaces the pending peek timer).
- Then `(.dwelling, .dwellElapsed)` must emit `.growPanel` even though the panel is already large, because the peek-sized frame differs from the expanded frame: track `panelIsPeekSized` and clear it when `.growPanel` is emitted or the panel shrinks.
- `(.peeking, .pointer(inside: false))` is a no-op (pointer was already outside). `.peekRequested` in `.dwelling`, `.expanded`, `.leaving`, `.collapsing` -> `[]` (dropped).
- `.reset` and `.idleGeometryChanged` keep their meaning; `.reset` also clears the peek-sized flag.

- [ ] **Step 1: Write failing tests** in `HoverMachineTests` (reducer only): `peekFromCollapsed` (exact effect list above, phase `.peeking`); `peekIgnoredUnlessCollapsed` (from `.dwelling`, `.expanded`, `.leaving`, `.collapsing`: `[]` and phase unchanged); `secondPeekRestartsTimer` (`[.startTimer(.peek)]`, no resize effects); `peekElapsedCollapses` (exact effects, then `collapseFinished(generation:)` -> phase `.collapsed`, effects `[.shrinkPanel]`); `hoverDuringPeekExpandsAndStaleTimerIsIgnored` (pointer in -> `.dwelling`; `dwellElapsed` -> effects start with `.growPanel`, contain `.setHotRegion(.expanded)`, `.animateExpand`; a later `.peekElapsed` in `.expanded` returns `[]`); `peekCollapseCompletionAfterRehover` (peek, `peekElapsed` -> `.collapsing`, pointer in -> `.dwelling`, then `collapseFinished` with the matching generation while dwelling -> `[.shrinkPanel]` (existing behaviour: the following `dwellElapsed` emits `.growPanel` again because the panel is no longer large), and `collapseFinished` with an older generation -> `[]`); `resetDuringPeek` (phase `.collapsed`, effects include `.cancelTimer`, `.snapCollapsed`, `.setHotRegion(.idle)`, `.shrinkPanel`). In `HoverControllerTests` with `ManualScheduler`: `peekReturnsTrueAndSchedulesDuration` (`peek(duration: .seconds(3))` returns true, `pendingCount == 1`, advancing 3 s collapses via the perform callback); `peekReturnsFalseWhenHovering` (pointer in and dwell elapsed first -> `false`, no timer); `hoverCancelsPeekTimer` (`pointer(inside: true)` replaces the 3 s timer with the 80 ms dwell timer); `peekTimerGoneAfterCollapse` (after `collapseFinished`, `hasPendingTimer == false`).
- [ ] **Step 2: Run** `swift test --filter "HoverMachineTests|HoverControllerTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** machine and controller changes. Keep `HoverMachine` `Sendable` and pure.
- [ ] **Step 4: Run** the filter, then `swift test`. Expected: all pass (existing hover tests unchanged).
- [ ] **Step 5: Commit** explicit paths, message `Peek: hover phase and controller`.

### Task 4: Device types, policy, client protocol and setting (PURE, Codex; parallel-safe with Tasks 2-3)

**Files:**
- Create: `Sources/ShimaCore/DeviceTypes.swift`, `Sources/ShimaCore/DevicePeekPolicy.swift`, `Sources/ShimaCore/DeviceClient.swift`, `Sources/ShimaCore/FakeDeviceClient.swift`
- Modify: `Sources/ShimaCore/SettingsStore.swift` (key `devicePopups`), `Sources/ShimaCore/SettingsModel.swift` (`devicePopupsEnabled`, `setDevicePopupsEnabled`), `Sources/ShimaCore/AppState.swift` (`devicePopupsEnabled`, `peek: PeekItem?`)
- Test: `Tests/ShimaCoreTests/DeviceTypesTests.swift`, `Tests/ShimaCoreTests/DevicePeekPolicyTests.swift`, extend `Tests/ShimaCoreTests/SettingsStoreTests.swift` and `SettingsModelTests.swift`

**Interfaces:**
- Produces:
  - `public enum DeviceKind: String, Sendable, CaseIterable { case headphones, earbuds, keyboard, mouse, trackpad, speaker, gamepad, other }` with `var symbolName: String` (SF Symbol per kind: earbuds `airpods.gen3`, headphones `headphones`, keyboard `keyboard`, mouse `computermouse`, trackpad `rectangle.and.hand.point.up.left`, speaker `hifispeaker`, gamepad `gamecontroller`, other `wave.3.right`), plus `static func classify(major: Int?, minor: Int?, name: String) -> DeviceKind` (rules, in order: name keywords first, case-insensitive: contains "airpods" or "buds" -> `.earbuds`; then class of device with `minor` as the 6-bit field IOBluetooth reports: major 4 (audio/video): minor 5 -> `.speaker`, minor 1, 2 or 6 -> `.headphones`; major 5 (peripheral): minor 16 -> `.keyboard`, 32 -> `.mouse`, 48 -> `.keyboard`; then remaining name keywords: "keyboard" or "keychron" -> `.keyboard`, "mouse" or "mx master" -> `.mouse`, "trackpad" -> `.trackpad`, "controller" or "dualsense" or "xbox" -> `.gamepad`; else `.other`). Real values from spike S1: AirPods 4 (ANC) major 4 minor 6; Keychron K3 major 5 minor 16.
  - `public struct DeviceEvent: Equatable, Sendable { address: String; name: String; kind: DeviceKind; batteryPercent: Int? }`
  - `public struct DevicePeek: Equatable, Sendable { title: String; subtitle: String; batteryText: String?; kind: DeviceKind; duration: Duration }` where `title == "Connected"`, `subtitle` is the trimmed name (`"Bluetooth device"` when empty, truncated to 40 characters with a trailing "…"), `batteryText` is `"82%"` for 0...100 and `nil` otherwise, `duration == .seconds(3)`.
  - `public enum PeekItem: Equatable, Sendable { case device(DevicePeek) }`
  - `public enum PeekDrop: Equatable, Sendable { case disabled, launchGrace, wakeGrace, repeated }`, `public enum PeekDecision: Equatable, Sendable { case show(DevicePeek), drop(PeekDrop) }`
  - `public struct DevicePeekPolicy: Sendable { init(startedAt: Date); mutating func decide(_ event: DeviceEvent, now: Date, enabled: Bool) -> PeekDecision; mutating func didWake(at: Date) }` (drop order: disabled, then within 3 s after `startedAt` because the system replays already-connected devices at registration, then within 10 s after `didWake`, then the same address shown within the last 5 s).
  - `@MainActor public protocol DeviceClient: AnyObject { var onConnect: (@MainActor (DeviceEvent) -> Void)? { get set }; func start(); func stop() }`; `FakeDeviceClient` with `startCount`, `stopCount`, and `emit(_ event: DeviceEvent)`.
  - `SettingsStore.devicePopups: Bool` (default true; stored as "on"/"off" under key `devicePopups`), `setDevicePopups(_:)`; `SettingsModel.devicePopupsEnabled` mirrored into `AppState.devicePopupsEnabled` at init and on change, plus `onDevicePopupsChange` callback like the equalizer one. `AppState.peek: PeekItem?` (plain stored property, no hooks).

- [ ] **Step 1: Write failing tests:** `symbolNames` (every `DeviceKind` has a non-empty name; earbuds is `airpods.gen3`); classification table ("AirPods 4 (ANC)" with major 4 minor 6 -> `.earbuds`, the name beating the headphones class; "Keychron K3" with major 5 minor 16 -> `.keyboard`; major 5 minor 32 -> `.mouse`; "WH-1000XM5" major 4 minor 6 -> `.headphones`; "MX Master 3S" with no class data -> `.mouse`; unknown -> `.other`); `displayNameFallbackAndTruncation` (empty and whitespace-only name -> "Bluetooth device"; a 60-character name -> 40 characters ending in "…"); `batteryOutOfRangeIsHidden` (-1, 101 -> nil text; 0 -> "0%", 100 -> "100%"); policy: `disabledDrops`, `launchGraceDropsReplayedDevices` (event at +2.9 s after `startedAt` -> `.drop(.launchGrace)`, at +3.1 s -> show), `wakeGraceDropsWithinTenSeconds` (drop at +9.9 s, show at +10.1 s), `sameAddressWithinFiveSecondsDrops` (second event at +4.9 s -> `.drop(.repeated)`; at +5.1 s -> show; a different address within 5 s -> show); settings: default on, round trip through `InMemoryPreferenceStorage`, `AppState.devicePopupsEnabled` follows the model, an unknown stored value reads as on.
- [ ] **Step 2: Run** `swift test --filter "DeviceTypesTests|DevicePeekPolicyTests|SettingsStoreTests|SettingsModelTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** the files and settings changes above.
- [ ] **Step 4: Run** the filter, then `swift test`. Expected: pass, no warnings.
- [ ] **Step 5: Commit** explicit paths, message `Devices: types, peek policy, client protocol and setting`.

### Task 5a: Peek effects in the panel controller (GLUE, Codex; needs Tasks 2-4)

**Files:**
- Modify: `Sources/Shima/IslandPanelController.swift`, `Sources/Shima/Log.swift` (`Log.peek`, category `peek`)

**Interfaces:**
- Consumes: `HoverEffect.growPanelForPeek/.animatePeekIn`, `HoverController.peek(duration:)`, `IslandLayout.peekPanelFrame`, `AppState.peek` (Tasks 2-4).
- Produces: `IslandPanelController.showPeek(_ item: PeekItem, duration: Duration) -> Bool` (sets `state.peek` first, calls `hover.peek(duration:)`; on `false` restores the previous `state.peek`, logs `peek dropped`, returns false).

**Effects** (in `perform(_:)`):
- `.growPanelForPeek` -> set the panel frame to `IslandLayout.peekPanelFrame(notch:)` using the same no-animation transaction as `setPanelFrame` (extend `setPanelFrame` with a frame kind instead of duplicating it).
- `.animatePeekIn` -> `withAnimation(Self.spring) { state.mode = .peek }`; log `peek shown <kind>`.
- When the mode returns to `.collapsed` or becomes `.expanded`, clear `state.peek` and log `peek dismissed`; `.animateExpand` also clears it; `.snapCollapsed` (reset, display change) clears it too, so no path leaves `state.mode == .peek` behind.
- The animation parameters stay `Self.spring`; Claude may tune feel in 5b.

- [ ] **Step 1:** Implement the above. `swift build` warning-free; read `perform(_:)` once more for any path that leaves `.peek` set after `reset` or `place(on:)`.
- [ ] **Step 2:** Run `swift build && swift test`. Expected: pass.
- [ ] **Step 3: Commit** explicit paths, message `Peek: panel effects and showPeek`.
- [ ] **Step 4: Report** to the user that 5b (Claude) can start.

### Task 5b: Peek UI (VIEW, **Claude**)

**Files:** Create `Sources/ShimaCore/PeekLayout.swift`, `Sources/Shima/PeekContent.swift`; modify `Sources/Shima/IslandView.swift` (peek overlay; fill rules treat `.peek` like `.expanded`; collapsed wings unchanged); test `Tests/ShimaCoreTests/PeekLayoutTests.swift` (every rect inside 340 x 76; battery rect does not overlap the subtitle rect; badge 30 x 30).
Values from the spec's Layout table; the badge glyph is `Image(systemName: kind.symbolName)` with `airpods.gen3` falling back to `airpods` when `NSImage(systemSymbolName:)` returns nil; the overlay is `allowsHitTesting(false)` and only visible when `state.mode == .peek`.

### Task 6a: Device service, IOBluetooth client and wiring (GLUE, Codex; needs Task 1's spike file)

**Files:**
- Create: `Sources/Shima/IOBluetoothDeviceClient.swift`, `Sources/Shima/DeviceService.swift`
- Modify: `Sources/Shima/AppDelegate.swift`, `scripts/bundle.sh` (the Bluetooth usage-description plist key; mandatory)

**Behaviour:**
- `IOBluetoothDeviceClient: DeviceClient` implements the spike's path (`docs/superpowers/spikes/2026-11-23-device-spikes.md`): `IOBluetoothDevice.register(forConnectNotifications:selector:)` registered once in `start()`; each notification is delivered on the main actor and **dropped when `device.isConnected()` is false**; otherwise mapped to `DeviceEvent` with `name` (address string if nil), `addressString`, `DeviceKind.classify(major: deviceClassMajor, minor: deviceClassMinor, name:)`, and battery from the private selectors `batteryPercentLeft`, `batteryPercentRight`, `batteryPercentSingle`, `batteryPercentCombined`, each read through key-value coding only after `responds(to:)` (0 or missing means unknown; show the lowest non-zero left/right, else single or combined if non-zero, else nil; never the case). `stop()` unregisters. `DeviceService` creates the policy with `DevicePeekPolicy(startedAt: Date())` right when it calls `client.start()`.
- `DeviceService` (`@MainActor`) owns the client, a `DevicePeekPolicy` and a reference to the island controller. On each `onConnect` it asks the policy (`now: Date()`, `enabled: state.devicePopupsEnabled`) and, on `.show`, calls `islandController.showPeek(.device(peek), duration: peek.duration)`; logs `device connect kind=<kind> -> shown|drop(<reason>)` (the device name is logged with `privacy: .private`, kind and decision `.public`). Observes `NSWorkspace.didWakeNotification` and calls `policy.didWake(at:)`. Starts at launch; no timers.
- `SHIMA_FAKE_DEVICES=1` replaces the real client by `FakeDeviceClient` and listens for the distributed notification `local.shima.fake-device` with object `"connect|<name>|<kind>|<battery or ->"`; malformed input logs `device fake bad command` and is ignored.

- [ ] **Step 1:** Implement client, service and wiring. `swift build` warning-free.
- [ ] **Step 2:** `swift test` passes; launch with `SHIMA_FAKE_DEVICES=1 scripts/run.sh` and confirm with `scripts/with-log.sh` that `swift scripts/drive.swift "fake-device connect|Test AirPods|earbuds|82"` (added in 7a) logs `device connect ... shown` and `peek shown earbuds`.
- [ ] **Step 3: Commit** small explicit-path commits.

### Task 6b: "Device pop-ups" Settings row (VIEW, **Claude**)

Modifies `Sources/Shima/SettingsView.swift` (and `SettingsText.swift` for copy) so the General page has the "Device pop-ups" row from the mockup (subtitle "A short banner under the notch when a Bluetooth device connects."), wired to `SettingsModel.setDevicePopupsEnabled`, logging `settings devicePopups on|off saved`; `scripts/verify-settings.sh` extended with the new row.

### Task 7a: Fake command and peek verification (SCRIPT, Codex)

**Files:** Modify `scripts/drive.swift` (new `fake-device` step posting `local.shima.fake-device`); create `scripts/verify-peek.sh`.

**Checks** (`verify-peek.sh`, modelled on `verify-camera.sh`; requires `SHIMA_FAKE_DEVICES=1 SHIMA_FAKE_SPOTIFY=paused scripts/run.sh`; each pointer sequence under 2 minutes and announced):
1. Pointer away, `fake-device connect|Test AirPods|earbuds|82` -> log has `peek shown earbuds`; the window list (`scripts/shima-windows.swift`) shows the panel frame 376 x 84 centred on the notch.
2. After about 3 s: `peek dismissed` and the panel frame is back to the idle size; no pending timer (idle CPU unchanged per `verify-idle.sh`).
3. Second device during a peek: one `peek shown` per event, one dismissal, a single 3 s window after the last event.
4. Pointer enters the banner: the island opens once (`island content=` log) with no collapse race; moving away collapses normally.
5. Event while the island is open: log has `peek dropped` and no `peek shown`.
6. Same address twice within 5 s: second is `drop(repeated)`.
7. Settings toggle off: next event logs `drop(disabled)`.
8. `scripts/verify-focus.sh` during a peek shows the panel never became key or active.
- Regression: `swift test`, `scripts/verify-alignment.sh [--live|--expanded]`, `scripts/verify-live-hover.sh`, `scripts/verify-idle.sh [--playing]`, `scripts/verify-camera.sh` (with `SHIMA_FAKE_CAMERA=1`), `scripts/verify-settings.sh`. (`verify-view-layout.sh` is Claude's, Task 7b.)

- [ ] **Step 1:** Add the `fake-device` step; `swift build`.
- [ ] **Step 2:** Write `scripts/verify-peek.sh`; run it against the fake app. Expected: `PASS`.
- [ ] **Step 3:** Run the regression list. Expected: all pass.
- [ ] **Step 4: Commit** explicit paths, message `Devices: fake command and peek verification script`.

### Task 7b: Offscreen renders and mockup comparison (VIEW, **Claude**)

Adds `PeekContent.swift` to `scripts/verify-view-layout.sh`, peek cases to `scripts/view-layout-check.swift` (each device kind, with and without battery, a 60-character name truncated with no overlap with the battery text, low battery red), writes the renders to PNG and compares each against a headless-Chrome screenshot of the matching mockup state; mismatches are fixed in 5b until they agree.

### Task 8: Review and acceptance (Claude and the user)

- Whole-branch review by a fresh reviewer against the spec and Global Constraints, with special attention to the hover machine (races, generations, the peek-sized to expanded frame swap during hover). Correction wave and scoped re-review.
- Human checks in `docs/superpowers/device-popups-acceptance.md`: connect real AirPods and the Keychron (banner appears, name correct, battery shown or absent as the spike predicted); no banner within 10 s after waking the Mac; hovering during a banner opens the island; external display; the Settings toggle.
- Update `CLAUDE.md` and the memory index after acceptance.

## Self-review notes

- Spec coverage: peek mechanism (2, 3, 5); device events and banner content (4, 5, 6); quiet rules: wake grace, per-address limit, setting (4); gating while open or hovered (3); Settings toggle (4, 6); spike (1); fake mode and checks (6, 7); human checks (8). Non-goals have no tasks.
- Spec correction already applied: no disconnect banners; peek duration lives in `HoverController`, not the reducer input.
- Names consistent across tasks: `IslandMode.peek`, `HotRegion.peek`, `HoverPhase.peeking`, `HoverController.peek(duration:)`, `IslandLayout.peekPanelFrame`, `PeekItem`, `DevicePeek`, `DevicePeekPolicy`, `DeviceClient`, `FakeDeviceClient`, `PeekLayout`, `PeekContent`, `DeviceService`.
