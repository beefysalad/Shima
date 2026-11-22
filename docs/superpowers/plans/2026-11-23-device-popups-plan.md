# Device pop-ups and peek banner Implementation Plan

> **For agentic workers (Codex):** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax. Read `CLAUDE.md` first (project rules and gotchas). Work in a worktree `.worktrees/devices` on branch `devices` (`git worktree add .worktrees/devices -b devices`), started from `main` after the calendar branch is merged (both touch `IslandView.swift`, `IslandPanelController.swift`, `AppDelegate.swift`, `scripts/bundle.sh`). Task labels: **PURE** (ShimaCore), **GLUE** (Shima app), **SCRIPT**, **HUMAN/CLAUDE** (not for Codex; skip and report when you reach one).

**Goal:** When a Bluetooth device connects, the collapsed island drops a 3-second "Connected, <name>" banner (the peek), built on a reusable peek mechanism in the hover state machine.

**Architecture:** `IslandMode.peek` + `HoverPhase.peeking` in the existing hover machine own panel size, hot region and generations (no second owner). A pure `DevicePeekPolicy` decides what to show; a `DeviceClient` protocol (IOBluetooth in the app, fake in tests) reports connections; `DeviceService` glues them to `IslandPanelController`.

**Tech Stack:** Swift 6 toolchain, SwiftPM only, Swift Testing (no XCTest), IOBluetooth (app target only), SwiftUI. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-11-23-device-popups-design.md`. Mirror these existing files: `Sources/ShimaCore/{HoverMachine,HoverController,IslandLayout}.swift`, `Tests/ShimaCoreTests/{HoverMachineTests,HoverControllerTests,IslandLayoutTests,ManualScheduler}.swift`, `Sources/Shima/IslandPanelController.swift`, `Sources/ShimaCore/{SettingsStore,SettingsModel}.swift`, `Sources/Shima/SpotifyService.swift` (fake-mode notification pattern).

## Global Constraints

- `ShimaCore` must not import AppKit or IOBluetooth. IOBluetooth lives in `Sources/Shima/`.
- SwiftPM only; no third-party dependencies.
- No polling and no timers while idle. The only timer is the hover controller's peek timer, alive only while a peek is on screen. Detection is notification-driven.
- The island panel never steals focus (a peek must not activate shima or take key status). Hover must keep working during a peek.
- The collapsed idle size and the expanded 400 x 200 island are unchanged. The panel frame is resized only by the hover machine's effects, never by a view.
- Nothing may enlarge the island root `ZStack`; the peek content is an overlay with explicit frames.
- The real UI must match `mockup/index.html` (Task 0 extends it first). Peek island: 460 x 84, bottom radius 24, ear radius 12.
- Commit messages: plain, no attribution trailers. Stage explicit paths, never `git add -A`. No signing identifiers, `.build`, `dist` in commits. Never use real Bluetooth in scripts: fake mode only. Kill the app by pid, never `pkill -x Shima`.
- The terminal has no Screen Recording permission: verify with logs, window list, CGEvent input and offscreen renders.
- Info.plist key `NSBluetoothAlwaysUsageDescription` is added only if Task 1 (spike) says the chosen path needs it.

## Review Focus

1. A peek request while the pointer already hovers the notch (phase not collapsed) must be dropped, not shown under the cursor (Task 3: `peekIgnoredUnlessCollapsed`).
2. Hover entering the banner during a peek must open the full island exactly once and cancel the peek timer; a late `peekElapsed` must not collapse it (Task 3: `hoverDuringPeekExpandsAndStaleTimerIsIgnored`).
3. A collapse completion from a peek arriving after a re-hover must be ignored (generation numbers) (Task 3: `peekCollapseCompletionAfterRehover`).
4. A second device event during a peek replaces the content and restarts the timer without resizing the panel (Task 3: `secondPeekRestartsTimer`; Task 5: `secondPeekReplacesContent`).
5. Device names that are empty, very long, or contain only whitespace; battery values outside 0...100 (Task 4: `displayNameFallbackAndTruncation`, `batteryOutOfRangeIsHidden`).

---

### Task 0: Mockup (HUMAN/CLAUDE, not Codex)

Claude extends `mockup/index.html` with the device peek variants (earbuds, keyboard, mouse, generic; with and without battery) inside the existing 460 x 84 peek, and the Settings General row "Device pop-ups". The user approves it. The approved glyph shapes and the peek content rects/sizes are appended to the spec as a "Peek layout table", used by Task 5. If the table is missing when you reach Task 5, stop and report.

### Task 1: Spike S1, Bluetooth notifications (CLAUDE + HUMAN, not Codex)

Claude, with the user connecting and disconnecting the Keychron K3 and AirPods 4, answers the questions in the spec's "Spike S1" section and writes `docs/superpowers/spikes/2026-11-23-device-spikes.md` containing: the chosen detection path (IOBluetooth connect notifications or the IOKit matching fallback), whether `NSBluetoothAlwaysUsageDescription` is needed, the exact API calls and property names that yield name, address, class of device and (if any) battery, and a battery yes/no per device. Codex's Task 6 reads this file; if it is missing, stop and report. Tasks 2-5 do not depend on it and can run first.

### Task 2: Peek geometry (PURE)

**Files:**
- Modify: `Sources/ShimaCore/IslandLayout.swift`, `Sources/ShimaCore/EqualizerMode.swift` (switches over `IslandMode`), `Sources/ShimaCore/CameraModel.swift` (verify only: `.peek` is not visible for the camera)
- Test: `Tests/ShimaCoreTests/IslandLayoutTests.swift`, `Tests/ShimaCoreTests/EqualizerModeTests.swift`

**Interfaces:**
- Produces:
  - `IslandMode.peek`
  - `HotRegion.peek`
  - `IslandLayout.peek = IslandShapeMetrics(width: 460, height: 84, bottomRadius: 24, earRadius: 12)`
  - `IslandLayout.metrics(for: .peek, notch:, live:)` returns `IslandLayout.peek`
  - `IslandLayout.peekPanelFrame(notch: CGRect) -> CGRect`: width `460 + 2*12 + 2*hoverMargin` (500), height `84 + hoverMargin` (92), centred on `notch.midX`, top edge at `notch.maxY` (same construction as the expanded `panelFrame`)
  - `IslandLayout.hotRect(.peek, notch:, live:, panelFrame:)` is the whole panel in local coordinates, like `.expanded`.

- [ ] **Step 1: Write failing tests** with the same `notch` fixture the existing tests use: `peekPanelFrameIsCentredAndTopAligned` (width 500, height 92, `midX == notch.midX`, `maxY == notch.maxY`); `peekHotRectIsWholePanel`; `peekMetricsAreMockupValues`; `peekDoesNotAnimateEqualizerOrCountAsExpanded` (`EqualizerPolicy`'s visible/animating functions treat `.peek` like `.collapsed`: the wings are hidden during a peek, so `isVisible(island: .peek, live: true, content: .track) == false`, `isAnimating(.animated, island: .peek, ...) == false`). Keep all existing layout tests unchanged.
- [ ] **Step 2: Run** `swift test --filter "IslandLayoutTests|EqualizerModeTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** the above; fix every `switch` over `IslandMode`/`HotRegion` the compiler flags (`swift build` lists them).
- [ ] **Step 4: Run** `swift build && swift test`. Expected: pass, no warnings.
- [ ] **Step 5: Commit** explicit paths, message `Peek: island mode and geometry`.

### Task 3: Hover machine peek phase (PURE)

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

### Task 4: Device types, policy, client protocol and setting (PURE, parallel-safe with Tasks 2-3)

**Files:**
- Create: `Sources/ShimaCore/DeviceTypes.swift`, `Sources/ShimaCore/DevicePeekPolicy.swift`, `Sources/ShimaCore/DeviceClient.swift`, `Sources/ShimaCore/FakeDeviceClient.swift`
- Modify: `Sources/ShimaCore/SettingsStore.swift` (key `devicePopups`), `Sources/ShimaCore/SettingsModel.swift` (`devicePopupsEnabled`, `setDevicePopupsEnabled`), `Sources/ShimaCore/AppState.swift` (`devicePopupsEnabled`, `peek: PeekItem?`)
- Test: `Tests/ShimaCoreTests/DeviceTypesTests.swift`, `Tests/ShimaCoreTests/DevicePeekPolicyTests.swift`, extend `Tests/ShimaCoreTests/SettingsStoreTests.swift` and `SettingsModelTests.swift`

**Interfaces:**
- Produces:
  - `public enum DeviceKind: String, Sendable, CaseIterable { case headphones, earbuds, keyboard, mouse, trackpad, speaker, gamepad, other }` with `static func classify(major: Int?, minor: Int?, name: String) -> DeviceKind` (Bluetooth class-of-device: major 4 = audio/video, minor 1 = wearable headset, 2 = hands-free, 6 = headphones, 5 = loudspeaker -> `.speaker`; major 5 = peripheral, minor bits 0x40 = keyboard, 0x80 = pointing device (mouse), 0xC0 = combo -> keyboard; name fallback, case-insensitive: contains "airpods" or "buds" -> `.earbuds`, "keyboard" or "keychron" -> `.keyboard`, "mouse" or "mx master" -> `.mouse`, "trackpad" -> `.trackpad`, "controller" or "dualsense" or "xbox" -> `.gamepad`). Class-of-device input is the raw major/minor already split by the glue code; if Task 1's spike shows another shape, adapt the signature and note it in the report.
  - `public struct DeviceEvent: Equatable, Sendable { address: String; name: String; kind: DeviceKind; batteryPercent: Int? }`
  - `public struct DevicePeek: Equatable, Sendable { title: String; subtitle: String; batteryText: String?; kind: DeviceKind; duration: Duration }` where `title == "Connected"`, `subtitle` is the trimmed name (`"Bluetooth device"` when empty, truncated to 40 characters with a trailing "…"), `batteryText` is `"82%"` for 0...100 and `nil` otherwise, `duration == .seconds(3)`.
  - `public enum PeekItem: Equatable, Sendable { case device(DevicePeek) }`
  - `public enum PeekDrop: Equatable, Sendable { case disabled, wakeGrace, repeated }`, `public enum PeekDecision: Equatable, Sendable { case show(DevicePeek), drop(PeekDrop) }`
  - `public struct DevicePeekPolicy: Sendable { init(); mutating func decide(_ event: DeviceEvent, now: Date, enabled: Bool) -> PeekDecision; mutating func didWake(at: Date) }` (drop order: disabled, then within 10 s after `didWake`, then the same address shown within the last 5 s).
  - `@MainActor public protocol DeviceClient: AnyObject { var onConnect: (@MainActor (DeviceEvent) -> Void)? { get set }; func start(); func stop() }`; `FakeDeviceClient` with `startCount`, `stopCount`, and `emit(_ event: DeviceEvent)`.
  - `SettingsStore.devicePopups: Bool` (default true; stored as "on"/"off" under key `devicePopups`), `setDevicePopups(_:)`; `SettingsModel.devicePopupsEnabled` mirrored into `AppState.devicePopupsEnabled` at init and on change, plus `onDevicePopupsChange` callback like the equalizer one. `AppState.peek: PeekItem?` (plain stored property, no hooks).

- [ ] **Step 1: Write failing tests:** classification table (`AirPods 4` with no class data -> `.earbuds`; major 5 minor 0x40 -> `.keyboard`; "MX Master 3S" -> `.mouse`; unknown -> `.other`; major/minor beat the name); `displayNameFallbackAndTruncation` (empty and whitespace-only name -> "Bluetooth device"; a 60-character name -> 40 characters ending in "…"); `batteryOutOfRangeIsHidden` (-1, 101 -> nil text; 0 -> "0%", 100 -> "100%"); policy: `disabledDrops`, `wakeGraceDropsWithinTenSeconds` (drop at +9.9 s, show at +10.1 s), `sameAddressWithinFiveSecondsDrops` (second event at +4.9 s -> `.drop(.repeated)`; at +5.1 s -> show; a different address within 5 s -> show); settings: default on, round trip through `InMemoryPreferenceStorage`, `AppState.devicePopupsEnabled` follows the model, an unknown stored value reads as on.
- [ ] **Step 2: Run** `swift test --filter "DeviceTypesTests|DevicePeekPolicyTests|SettingsStoreTests|SettingsModelTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** the files and settings changes above.
- [ ] **Step 4: Run** the filter, then `swift test`. Expected: pass, no warnings.
- [ ] **Step 5: Commit** explicit paths, message `Devices: types, peek policy, client protocol and setting`.

### Task 5: Peek in the panel and the banner view (GLUE; needs Tasks 2-4 and Task 0's Peek layout table)

**Files:**
- Create: `Sources/ShimaCore/PeekLayout.swift`, `Sources/Shima/PeekContent.swift`
- Modify: `Sources/Shima/IslandPanelController.swift`, `Sources/Shima/IslandView.swift`, `Sources/Shima/WingsView.swift` (hidden while `state.mode == .peek`), `Sources/Shima/Log.swift` (`Log.peek`, category `peek`)
- Test: `Tests/ShimaCoreTests/PeekLayoutTests.swift`

**Interfaces:**
- Produces: `PeekLayout` constants from the table (badge, title, subtitle, battery rects inside the 460 x 84 island, top-left local coordinates); `IslandPanelController.showPeek(_ item: PeekItem, duration: Duration) -> Bool` (sets `state.peek` first, calls `hover.peek(duration:)`; on `false` restores the previous `state.peek` and returns false); `PeekContent` (SwiftUI overlay, opacity 0 unless `state.mode == .peek`, `allowsHitTesting(false)` so hover and focus are untouched).

**Panel effects** (in `perform(_:)`):
- `.growPanelForPeek` -> `setPanelFrame` with `IslandLayout.peekPanelFrame(notch:)` (same transaction pattern as `setPanelFrame`; extend it with a `kind` parameter instead of duplicating).
- `.animatePeekIn` -> `withAnimation(Self.spring) { state.mode = .peek }`; log `peek shown <kind>`.
- `.animateCollapse` / `.snapCollapsed` unchanged (they set `.collapsed`); when the mode returns to `.collapsed` or `.expanded`, clear `state.peek` and log `peek dismissed`.
- `.animateExpand` also clears `state.peek`.
- `IslandView`: shape metrics already come from `IslandLayout.metrics(for: state.mode, ...)`; add the `PeekContent` overlay; the fill rules treat `.peek` like `.expanded` (opaque black).

- [ ] **Step 1: Write failing tests** `PeekLayoutTests`: every rect lies inside 460 x 84; the battery text rect does not overlap the subtitle rect; the badge is 34 x 34 (mockup value).
- [ ] **Step 2: Run** `swift test --filter PeekLayoutTests`. Expected: FAIL; then implement `PeekLayout` and run: PASS.
- [ ] **Step 3: Implement** the panel and view changes. `swift build` must be warning-free. Check by reading `perform(_:)` that no code path leaves `state.mode == .peek` after a `reset` or `place(on:)` (display change during a peek): `reset` -> `.snapCollapsed` already sets `.collapsed`; add `state.peek = nil` there.
- [ ] **Step 4: Run** `swift build && swift test`. Expected: pass.
- [ ] **Step 5: Commit** in small explicit-path commits (layout, panel effects, view).

### Task 6: Device service, IOBluetooth client and wiring (GLUE; needs Task 1's spike file)

**Files:**
- Create: `Sources/Shima/IOBluetoothDeviceClient.swift`, `Sources/Shima/DeviceService.swift`
- Modify: `Sources/Shima/AppDelegate.swift`, `Sources/Shima/SettingsView.swift` (General page row "Device pop-ups", matching the approved Settings mockup), `Sources/ShimaCore/SettingsText.swift` if copy lives there, `scripts/bundle.sh` (plist key only if the spike says so)

**Behaviour:**
- `IOBluetoothDeviceClient: DeviceClient` implements the path chosen in `docs/superpowers/spikes/2026-11-23-device-spikes.md` (connect notifications registered once in `start()`, delivered on the main actor, mapped to `DeviceEvent` using the spike's property names and `DeviceKind.classify`). `stop()` unregisters.
- `DeviceService` (`@MainActor`) owns the client, a `DevicePeekPolicy` and a reference to the island controller. On each `onConnect` it asks the policy (`now: Date()`, `enabled: state.devicePopupsEnabled`) and, on `.show`, calls `islandController.showPeek(.device(peek), duration: peek.duration)`; logs `device connect kind=<kind> -> shown|drop(<reason>)` (the device name is logged with `privacy: .private`, kind and decision `.public`). Observes `NSWorkspace.didWakeNotification` and calls `policy.didWake(at:)`. Starts at launch; no timers.
- `SHIMA_FAKE_DEVICES=1` replaces the real client by `FakeDeviceClient` and listens for the distributed notification `local.shima.fake-device` with object `"connect|<name>|<kind>|<battery or ->"`; malformed input logs `device fake bad command` and is ignored.
- The Settings toggle writes through `SettingsModel.setDevicePopupsEnabled` and logs `settings devicePopups on|off saved`.

- [ ] **Step 1:** Implement client, service, wiring, setting row. `swift build` warning-free.
- [ ] **Step 2:** Run `swift test` (expected pass) and launch with `SHIMA_FAKE_DEVICES=1 scripts/run.sh`; confirm with `scripts/with-log.sh` that `swift scripts/drive.swift "fake-device connect|Test AirPods|earbuds|82"` (added in Task 7) logs `device connect ... shown` and `peek shown earbuds`.
- [ ] **Step 3: Commit** small explicit-path commits.

### Task 7: Fake commands, checks and regression (SCRIPT)

**Files:**
- Modify: `scripts/drive.swift` (new `fake-device` step posting `local.shima.fake-device`), `scripts/verify-view-layout.sh` and `scripts/view-layout-check.swift` (add `PeekContent.swift`, render peek variants), `scripts/verify-idle.sh` only if it needs the new log lines
- Create: `scripts/verify-peek.sh`

**Checks** (`verify-peek.sh`, modelled on `verify-camera.sh`; requires `SHIMA_FAKE_DEVICES=1 SHIMA_FAKE_SPOTIFY=paused scripts/run.sh`; each pointer sequence under 2 minutes and announced):
1. Pointer away, `fake-device connect|Test AirPods|earbuds|82` -> log has `peek shown earbuds`; the window list (`scripts/shima-windows.swift`) shows the panel frame 500 x 92 centred on the notch.
2. After about 3 s: `peek dismissed` and the panel frame is back to the idle size; no pending timer (the log line from the hover controller or `verify-idle.sh` shows idle CPU unchanged).
3. Second device during a peek: one `peek shown` per event, one dismissal, a single 3 s window after the last event.
4. Pointer enters the banner: island opens once (`island content=` log) and no `peek dismissed` collapse races; moving away collapses normally.
5. Event while the island is open: log `device connect ... shown` is **not** present; the policy's decision is `shown` only when the hover controller accepts, so assert `peek dropped` (add this log line in `IslandPanelController.showPeek` when `hover.peek` returns false).
6. Same address twice within 5 s: second is `drop(repeated)`.
7. Settings toggle off (`SHIMA_SETTINGS_...` or the Settings window row via the existing `verify-settings.sh` pattern): next event logs `drop(disabled)`.
8. Focus: `scripts/verify-focus.sh` during a peek shows the panel never became key or active.
- Offscreen render check: the peek island fits 460 x 84 for each device kind, with and without battery, with a 60-character name (truncated, no overlap with the battery text).
- Regression: `swift test`, `scripts/verify-view-layout.sh`, `scripts/verify-alignment.sh [--live|--expanded]`, `scripts/verify-live-hover.sh`, `scripts/verify-idle.sh [--playing]`, `scripts/verify-camera.sh` (with `SHIMA_FAKE_CAMERA=1`), `scripts/verify-settings.sh`.

- [ ] **Step 1:** Add the `fake-device` step and the log line for dropped peeks; `swift build`.
- [ ] **Step 2:** Extend the offscreen checks; `scripts/verify-view-layout.sh`. Expected: PASS lines for all peek variants and the existing cases.
- [ ] **Step 3:** Write `scripts/verify-peek.sh`; run it against the fake app. Expected: `PASS`.
- [ ] **Step 4:** Run the regression list above. Expected: all pass.
- [ ] **Step 5: Commit** explicit paths, message `Devices: fake command and peek verification scripts`.

### Task 8: Review and acceptance (CLAUDE + HUMAN, not Codex)

- Whole-branch review by a fresh reviewer against the spec and Global Constraints, with special attention to the hover machine (races, generations, the peek-sized to expanded frame swap during hover). Correction wave and scoped re-review.
- Human checks in `docs/superpowers/device-popups-acceptance.md`: connect real AirPods and the Keychron (banner appears, name correct, battery shown or absent as the spike predicted); no banner for devices already connected at launch; no banner within 10 s after waking the Mac; hovering during a banner opens the island; external display; the Settings toggle.
- Update `CLAUDE.md` and the memory index after acceptance.

## Self-review notes

- Spec coverage: peek mechanism (2, 3, 5); device events and banner content (4, 5, 6); quiet rules: wake grace, per-address limit, setting (4); gating while open or hovered (3); Settings toggle (4, 6); spike (1); fake mode and checks (6, 7); human checks (8). Non-goals have no tasks.
- Spec correction already applied: no disconnect banners; peek duration lives in `HoverController`, not the reducer input.
- Names consistent across tasks: `IslandMode.peek`, `HotRegion.peek`, `HoverPhase.peeking`, `HoverController.peek(duration:)`, `IslandLayout.peekPanelFrame`, `PeekItem`, `DevicePeek`, `DevicePeekPolicy`, `DeviceClient`, `FakeDeviceClient`, `PeekLayout`, `PeekContent`, `DeviceService`.
