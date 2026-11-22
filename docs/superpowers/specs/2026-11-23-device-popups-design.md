# Device pop-ups (the "DynaConnect" idea) and the peek banner

Status: mockup approved 2026-11-23; drafted from the user's request ("airpods, keyboard etc"); the user approved the calendar design and asked for this one to be designed and planned alongside it. Calls marked **[My call]** are open to correction. Reference image: DynaConnect, a short banner under the notch saying "Connected / MX Master 3S". Built after `2026-11-23-calendar-reminders-design.md`.

## Intent

When a Bluetooth device connects (AirPods, a keyboard, a mouse), the collapsed island briefly drops a small banner, "Connected, <name>", with a device icon and the battery level when it is available, then folds away. It replaces the small system confirmation people miss. It also builds the **peek banner**, the transient, hover-independent presentation that the mockup already shows (460 x 84 in mockup units) and the design doc plans for later triggers (track change, calendar event, Claude "needs you").

## Goals

- Peek mechanism: the collapsed island can show a banner for a few seconds without any pointer interaction, then collapse. It never steals focus, never blocks hover (hovering during a peek opens the full island), and costs nothing while idle (one one-shot timer exists only while a peek is on screen).
- Device events: Bluetooth device connections, from system notifications, with the device name, a kind (headphones, earbuds, keyboard, mouse, trackpad, speaker, game controller, other), and battery percent when the system exposes it. **[My call]** Connections only: no disconnect banner (the reference shows none, and merging quick reconnects would need a delay timer).
- Banner content per the mockup: round badge with the device glyph, bold line "Connected", device name below, battery as "82%" on the right when known. **[My call]** The banner stays 3 s.
- Quiet by default: **[My call]** no banner for connections within 10 s after the Mac wakes (devices reconnect then); the same device address shows at most one banner per 5 s; a new device event replaces a banner already showing and restarts its timer; events while the island is open, being hovered, or on the Camera tab are dropped, not queued. No banner within 3 s of Shima registering for notifications (the system replays every already-connected device at registration; spike S1).
- A "Device pop-ups" on/off toggle on the Settings General page (default on).

## Non-goals

Disconnect banners; USB or Thunderbolt devices; low battery alerts; charging events; clicking the banner to do something; a device list tab; AirPods noise-control or case battery detail; Wi-Fi or hotspot events.

## Anti-goals

Polling for devices. (Changed by spike S1: IOBluetooth does need the Bluetooth permission, so the prompt appears on the first launch after the update; it is accepted.) Showing a banner that flickers during reconnect loops. Any change to the collapsed idle size.

## Constraints from the project

- Mockup first (project rule): add the device peek variants to `mockup/index.html` and get them approved before Swift UI. The mockup already has `.peek-row`, `.peek-badge` and a 460 x 84 peek; extend it, do not restyle it.
- Logic in `ShimaCore` with Swift Testing tests, no IOBluetooth or AppKit import there.
- Hover machine changes are the riskiest part of this milestone (see gotchas: resizing makes macOS re-send `mouseEntered`; collapse completion can arrive after a re-expand, handled by generation numbers). The pure reducer gets its tests first.
- Fake device mode for all automated checks; never rely on real Bluetooth in scripts.

## Approaches considered

1. **Peek as a new hover phase (`peeking`) plus `IslandMode.peek` (chosen).** One state machine owns panel size, hot region and generations, so peek, hover and collapse cannot race. Trade-off: the reducer and its tests grow.
2. Peek as an overlay on top of the collapsed state with its own panel resize. Simpler diff, but two owners of panel frame and hot region, and exactly the race the generation numbers exist to prevent. Rejected.
3. A second borderless panel for banners. Clean separation but a second window to place on every display change, a second thing that must never steal focus, more memory. Rejected for a POC.

Device detection: **IOBluetooth connect/disconnect notifications (`IOBluetoothDevice.register(forConnectNotifications:selector:)` and per-device disconnect registration) behind a `DeviceClient` protocol (chosen, pending spike S1).** Alternatives if S1 shows IOBluetooth misses the user's devices: an IOKit matching notification on `IOBluetoothDevice` and HID services (`IOServiceAddMatchingNotification`); CoreBluetooth is rejected because it needs a Bluetooth permission and cannot see classic devices' connection state. S1 decides; the plan has a branch for each outcome.

## Design

### Pure layer (`ShimaCore`)

- `IslandMode` gains `.peek`. `IslandLayout.peek = IslandShapeMetrics(width: 340, height: 76, bottomRadius: 22, earRadius: 10)` (real points; the mockup draws at its own larger scale), `metrics(for:)` and a peek-aware `panelFrame`/`hotRect` (a `HotRegion.peek`). Every existing `switch` over `IslandMode` is updated; `CameraModel` treats `.peek` as not visible.
- `HoverPhase` gains `.peeking`. New inputs: `peekRequested`, `peekElapsed`. New timer: `HoverTimer.peek`; its duration is held by `HoverController.peek(duration:)`, not by the reducer. New effects: `.growPanelForPeek`, `.animatePeekIn`. Rules: `peekRequested` is honoured only in `.collapsed`; in `.peeking` it restarts the timer; in any other phase it is ignored (the controller reports "dropped"). `peekElapsed` from `.peeking` goes to `.collapsing` with `animateCollapse(generation:)`, reusing the existing collapse completion. `pointer(inside: true)` while `.peeking` cancels the timer and goes to `.dwelling` (panel already large), then the normal dwell expands. `reset` and `idleGeometryChanged` keep their meaning.
- `AppState.peek: PeekItem?` with `PeekItem.device(DevicePeek)`; set when a peek starts, cleared when the island is collapsed again.
- `DeviceKind` with `classify(bluetoothMajor:minor:name:)` (class-of-device major/minor numbers plus a name fallback such as "AirPods"), `DeviceEvent { address, name, kind, batteryPercent? }` (connections only), `DevicePeek` (the display strings: title, subtitle, battery text, glyph, duration).
- `DevicePeekPolicy` (pure): inputs an event, the time, the last wake time and the on/off setting; outputs `show(DevicePeek)` or `drop(reason)`; implements the wake grace, the per-address 5 s limit and the setting. Island-state gating is the hover machine's job (it ignores `peekRequested` unless collapsed or already peeking).
- `DeviceClient` protocol (`@MainActor`): `start()`, `stop()`, `onConnect`. `FakeDeviceClient` for tests and fake mode.
- `SettingsStore` key `devicePopups` ("on"/"off", default on); `SettingsModel.devicePopupsEnabled` and setter, mirrored into `AppState` like the equalizer mode.

### Glue (`Shima`)

- `DeviceService`: owns the IOBluetooth client (or the S1 fallback), registers once at launch, forwards events through the policy to the `IslandPanelController`, which calls the hover controller's new `peek(duration:)`. Wake and sleep notifications feed the grace window. No timers other than the hover controller's peek timer.
- `IslandPanelController` handles the new effects (grow to the peek frame, animate the shape to `IslandLayout.peek`, show content). `IslandView` gets a `PeekContent` overlay drawn from `PeekLayout` constants in `ShimaCore`.
- Fake mode `SHIMA_FAKE_DEVICES=1`: `drive.swift` `fake-device connect "<name>" <kind> [battery]` posts `local.shima.fake-device`; logs `device fake ...` and `peek shown/dismissed` lines.
- Info.plist: `NSBluetoothAlwaysUsageDescription` is mandatory (spike S1: without it the process is killed at the first IOBluetooth call).
- Settings General page gets the toggle (matches an updated Settings mockup).

### Spike S1 (Claude, before the glue tasks; needs the user to connect and disconnect two devices)

Questions: does the IOBluetooth connect notification fire for the Keychron K3 and AirPods 4 on this Mac; does it need a Bluetooth permission; what name and class-of-device values arrive; is battery readable for each (candidates: `IOBluetoothDevice` properties, the IORegistry `BatteryPercent` key, `system_profiler` fields) and from which API without private frameworks. Output: `docs/superpowers/spikes/2026-11-23-device-spikes.md` with the chosen path and a yes/no on battery per device. Battery is optional: if it is not cleanly readable it is simply not shown **[My call]**.

## What is left to the builder

Glyph drawing for each kind (outlined like the header glyphs), spring parameters, test names, and anything the Layout table below leaves open.

## Verification

Automated: `swift test` (reducer, policy, classify, settings), `verify-view-layout.sh` extended for the peek frame, fake-mode run with `drive.swift` (connect peek appears and folds after the timer, hover during peek opens the island, event during open island is dropped, repeat within 5 s dropped, toggle off), `verify-focus.sh` (the panel never takes focus during a peek), `verify-idle.sh` (no timer or CPU while idle; peek timer gone after dismissal), logs. Human: real AirPods and keyboard connect, battery shown or absent as per S1, no flicker on real reconnect, behaviour with the external display. Recorded in `docs/superpowers/device-popups-acceptance.md`.


## Layout table (Task 0 output, real points)

Mockup: `mockup/index.html` ("Simulate" > "Bluetooth device connects"; Settings > General > "Device pop-ups"). The mockup draws at its own larger scale (peek 460 x 84 there); real values below. **Glyphs: the real app uses SF Symbols** (the mockup's hand-drawn `DEVGLYPH` paths are only a stand-in for them, since SF Symbols cannot be embedded in a web page): earbuds `airpods.gen3` (fall back to `airpods`), headphones `headphones`, keyboard `keyboard`, mouse `computermouse`, trackpad `rectangle.and.hand.point.up.left`, speaker `hifispeaker`, gamepad `gamecontroller`, other `wave.3.right`; 15 pt, medium weight, white, centred in the badge. The mapping is a pure `DeviceKind.symbolName` in `ShimaCore`. The battery glyph is the mockup's `battGlyph` (20 x 10).

- **Peek island:** 340 x 76 pt, bottom radius 22, ear radius 10, centred on the notch, top aligned with the screen; the top 32 pt strip overlays the notch and is unchanged (the collapsed wings stay as they are, as in the mockup). Panel frame while peeking: 376 x 84 (island + ears + 8 pt margin each side and bottom).
- **Content row (y 32..76):** badge circle 30 x 30 at (22, 38), fill white 13%, glyph 17 pt centred. Title "Connected" rect (62, 39, 190, 16), 13 pt semibold. Device name rect (62, 56, 190, 14), 11.5 pt regular, 62% white, one line, tail truncation (up to 256 wide when there is no battery). Battery group right-aligned to x 318, vertically centred at y 55: text "82%" 11.5 pt semibold tabular 62% white, 8 pt gap, battery glyph 20 x 10 (fill width proportional to percent). At 15% or below, text and fill use `#FF6961`. No battery value: the group is absent.
- **Timing:** banner 3 s; hover opens the island immediately (existing hover dwell).
- **Settings:** General page, "Device pop-ups" row with the subtitle "A short banner under the notch when a Bluetooth device connects." and a toggle, in the same group as the display options (default on).
