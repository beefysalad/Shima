# shima M1 (Spotify now playing, live indicator, controls) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While Spotify plays, the collapsed island grows 33 pt wings (mini artwork left, a Core Animation equalizer right); the open island shows artwork, title, artist, a read-only progress bar and working previous / play-pause / next buttons. Everything is event-driven, nothing ever launches Spotify, the panel never takes focus, and the Automation grant survives rebuilds.

**Architecture:** All Spotify decisions live in `ShimaCore` as pure, tested values: `NowPlaying` with `position(at:)`, a parsed `SpotifyReading`, the `SpotifyModel` reducer that emits `SpotifyChange`s (the seam M2's event bus will forward), a `SpotifyRequestGate` (coalescing, sequence and pid tags), a `SpotifyClient` protocol with a `FakeSpotifyClient`, and a `@MainActor SpotifyCoordinator` that applies results to `AppState`. The live geometry is two more pure pieces: `IslandLayout` idle frame and hot rect as functions of `(notch, live)`, and one new `HoverMachine` input, `.idleGeometryChanged`. `Shima` is glue: raw Apple Events by pid on a private serial queue, the distributed-notification and workspace observers, the artwork cache, the equalizer `NSViewRepresentable`, the wings and open-island SwiftUI views, a first-mouse hosting view for the buttons, and a fake mode (`SHIMA_FAKE_SPOTIFY`) that drives the real UI without Spotify.

**Tech Stack:** Swift 6.4.2 toolchain (language mode 6, `swift-tools-version:6.0`), SwiftPM, AppKit + SwiftUI (macOS 14+), Observation, Core Animation, Foundation `NSAppleEventDescriptor`, `URLSession` (ephemeral), ImageIO, os.Logger, Swift Testing. No third-party packages.

**Spec:** `docs/2026-11-20-notch-design.md`. **Section 8 (M1 design) is authoritative**: decisions 8.1, behavior 8.2, acceptance criteria 8.3 (1-8), architecture 8.4, verified/unverified 8.5, verification 8.6, scope 8.7. Context: section 2 (anti-goals, including the idle-CPU exception), 3 (constraints, signing), 5.2, 6.x. M0 facts: `docs/superpowers/m0-acceptance.md`, `docs/superpowers/spikes/2026-11-21-m0-spikes.md`. Visual reference: `mockup/index.html` lines 141-260 (collapsed `.slot`, `.mini-art`, `.wave`) and 600-760 (`renderMusic`), read only, never modify.

## Global Constraints

- SwiftPM only, no `.xcodeproj`. `swift build`, `swift test`. Swift Testing only (`import Testing`, `@Suite`, `@Test`, `#expect`); no XCTest. Baseline before Task 1: `swift test 2>&1 | tail -1` starts with `✔ Test run with 59 tests in 7 suites passed`.
- No third-party dependencies. Do not touch `~/.claude/settings.json` or any file outside the repo. Never modify `mockup/index.html`. Do not run `tccutil` (it edits the system TCC database).
- Logic in `ShimaCore` (no `import AppKit`, no `import SwiftUI` there; Foundation and CoreGraphics are fine) with tests. AppKit/SwiftUI glue in `Shima`. `shimactl` untouched.
- **Spotify safety.** Never launch Spotify from a script, test or app code. Never target Spotify by bundle id or name in an Apple Event, never use `NSAppleScript` or `tell application`; events go only to a pid from `NSRunningApplication`. Never play music on the user's account from automation: every step that needs real Spotify running, playing or receiving a command is a **HUMAN** step, done by the user in a **muted Spotify Private Session**. Everything else uses fake mode (`SHIMA_FAKE_SPOTIFY=playing|paused`).
- **Signing.** `scripts/bundle.sh` signs with `SHIMA_SIGN_ID` when set, else ad-hoc. The identity is the existing personal one: `SHIMA_SIGN_ID='Apple Development: jpatrickzephyr@gmail.com (<cert-id>)'`. Creating certificates or writing to the keychain is not allowed. The first `codesign` with that identity shows "codesign wants to access key": that step is **HUMAN** (the user chooses Allow or Always Allow; Always Allow edits that key's access list, which is the user's call, not ours). Automated fake-mode runs build **ad-hoc** (leave `SHIMA_SIGN_ID` unset) so no prompt blocks them. Every run in real mode while Spotify is running uses `SHIMA_SIGN_ID` (Task 17 adds a guard in `run.sh`).
- Launch the app only through `scripts/run.sh` (which uses `open`), so the Automation prompt is attributed to Shima, not to the terminal.
- Idle rule: with Spotify not playing, no timers, no event monitors, no polling, no running animations (M0 rule, unchanged). **Exception (section 2):** while Spotify plays and the island is collapsed and live, the equalizer's Core Animation animations run. `TimelineView` runs only while the island is open and playing. Nothing else repeats.
- The panel never becomes key or main and never activates the app, including when its buttons are clicked.
- Real-machine facts (measured in M0, 2026-11-21, macOS 26.6.2): built-in screen `1470 x 956` pt; notch `x 646..825, w 179, h 32` (AppKit `(646, 924, 179, 32)`); menu bar 33 pt (`visibleFrame.maxY = 923`); the first status item right of the notch starts at **x 860** (gap 35 pt). Expanded island `360 x 165` (bottom radius 24, ear 10); expanded panel `396 x 173`, AppKit `(537.5, 783, 396, 173)`, CG `x 537.5..933.5, y 0..173`. Island left edge in screen coordinates while expanded: `735.5 - 180 = 555.5`. **Live frame:** notch + 33 pt each side = `245 x 32`, CG `x 613..858, y 0..32`, AppKit `(613, 924, 245, 32)`.
- Timing unchanged: dwell `80 ms`, collapse debounce `300 ms`, spring `.spring(response: 0.35, dampingFraction: 0.8)`.
- Automation evidence (as in M0): synthetic mouse and key input through CGEvent (`scripts/drive.swift`, Task 2), `os.Logger` output read with `/usr/bin/log stream` (in zsh, `log` is a builtin: always write `/usr/bin/log`), and the CG window list (`scripts/shima-windows.swift`). The terminal has **no Screen Recording permission**: no screenshots or video, so anything visual is a HUMAN glance. In menu tests, hover an item about 150 ms before clicking it (`drive.swift`'s `click` does this).
- Pointer coordinates used by scripts are global top-left CG points on this Mac: notch centre `N = 735 16`, away `A = 735 400`, left wing `W = 630 16`, open-island controls (Task 11): previous `742.5 128`, play/pause `786.5 128`, next `830.5 128`, a non-button opaque point (artwork) `600 60`, first status item `872 16`.
- One small commit per task, explicit `git add <paths>`, never `git add -A`. Commit messages have **no tool-attribution trailers** (a hook enforces it).
- Test counts in "Expected" lines assume the plan order. If tasks run in a different order, check that the number grew by the task's own count.

## Review Focus

The risks a reviewer must check across tasks. Each line names the owning test or check.

1. **Live-frame change versus the hover machine.** Spotify starts or stops while the pointer is on the notch, during the 80 ms dwell, mid-expand, or mid-collapse after a re-entry. Expected: exactly one frame change per transition, the idle frame changes only while the panel is small, a stale collapse completion never shrinks a re-expanded panel, and the `mouseEntered` that macOS re-sends after every resize is a no-op. Tests: `geometryChangeWhileCollapsingWaits`, `geometryChangeWhileDwellingLargeWaitsForCollapseFinish`, `staleCollapseFinishAfterGeometryChangeIgnored`, `geometryChangeKeepsPointerDedupe` (Task 12), `liveToggleWhileDwellingKeepsOneTimer` (Task 12), and sequences D, F, G of `scripts/verify-live-hover.sh` (Task 15).
2. **Apple Events never launch Spotify.** No `NSAppleScript`, no `tell application`, no bundle-id target; no event when there is no pid; no event on `didLaunchApplication`. Checks: Spike 2 dead-pid result, `launchSendsNoAppleEvents`, `commandsOnlyWhenRunning` (Task 9), the static grep in Task 16 Step 4, and the criterion-3 run in Task 17 (`pgrep -x Spotify` stays empty).
3. **Stale results after Spotify quits** (a snapshot in flight, a late "Stopped" broadcast, an artwork download for the old track, a relaunch with a new pid). Expected: dropped, never shown, never a live indicator after quit. Tests: `resultAfterInvalidateIsDropped`, `resultFromOldPidIsDropped` (Task 10), `readingWhileNotRunningIsIgnored` (Task 8), `readingAfterTerminateIsIgnored`, `terminateClearsStateAndInvalidatesClient` (Task 9), the `artwork dropped stale` check (Task 18).
4. **Threading and isolation.** Apple Events only on `SpotifyScripting`'s private serial queue, never the main thread (a 2 s timeout or a pending Automation prompt must not freeze hover); results applied only on the main actor; `@unchecked Sendable` appears only on `SpotifyScripting`; notification `userInfo` is parsed into a `Sendable` value inside the callback. Checks: `dispatchPrecondition` in Task 16, `grep -rn "unchecked Sendable" Sources` (Task 16 Step 4), Swift 6 language mode builds without warnings about isolation.
5. **Clicks on the non-key panel do not steal focus.** A button click acts on the first click, `NSApp.isActive` stays false, the panel never becomes key, the frontmost app is unchanged, a click on a non-button island pixel does nothing. Checks: Spike 4, Task 21 Step 4, `scripts/verify-focus.sh --clicks` (Task 22).
6. **Equalizer layer lifecycle.** Animations are added idempotently, the view keeps a stable identity (never inside an `if`), pausing removes the animations and sets the rest transform, they come back after `orderOut`/`orderFront` and after occlusion, and nothing animates while paused, expanded, or not live. Checks: Spike 5 lifecycle table, Task 19 Step 4 (`eq animating`/`eq frozen` exactly once per transition, `anims=4`).
7. **Idle-CPU exception boundary.** The only repeating work is the equalizer while live+playing+collapsed and `TimelineView` while open+playing. A `TimelineView` that stays in the hierarchy at opacity 0 would tick while collapsed: it must be constructed only in the open+playing branch. Checks: Task 20 Step 5 (`progress tick` counts), `scripts/verify-idle.sh` strict and `--playing` (Task 23) with the `repeatCount`/`TimelineView` allowlist.

---

## File Map

| File | Status | Task | Responsibility |
|---|---|---|---|
| `scripts/bundle.sh` | modify | 2 | `SHIMA_SIGN_ID` (else ad-hoc), `--timestamp=none`, `NSAppleEventsUsageDescription` |
| `scripts/drive.swift` | create | 2 | CGEvent pointer/key steps and `fake <cmd>` distributed notifications, with timestamps |
| `Sources/Shima/SpotifyAppleEvents.swift` | create | 2 | raw `NSAppleEventDescriptor` helpers: property specifiers, `getd`, commands, error codes |
| `scripts/with-log.sh` | create | 3 | capture shima's unified log while a command runs |
| `Sources/Shima/EqualizerView.swift` | create | 5 | Core Animation 4-bar equalizer (`NSView` + `NSViewRepresentable`) |
| `docs/superpowers/spikes/2026-11-21-m1-spikes.md` | create | 1-5 | spike results and decisions |
| `Sources/ShimaCore/NowPlaying.swift` | create | 6 | `PlaybackState`, `SpotifyCommand`, `NowPlaying`, `position(at:)`, `PlaybackTime` |
| `Sources/ShimaCore/SpotifyReading.swift` | create | 7 | `SpotifyReading`, `ReadingSource`, payload parsing, artwork URL policy |
| `Sources/ShimaCore/SpotifyModel.swift` | create | 8 | `SpotifyEvent`, `SpotifyAvailability`, `SpotifyChange`, `NowPlayingContent`, `SpotifyModel` |
| `Sources/ShimaCore/SpotifyClient.swift` | create | 9 | `SpotifyClient` protocol |
| `Sources/ShimaCore/FakeSpotifyClient.swift` | create | 9 | `FakeSpotifyClient`, `FakeSpotifyMode` |
| `Sources/ShimaCore/SpotifyCoordinator.swift` | create | 9 | applies events to `AppState`, refresh policy, live/changes/artwork callbacks |
| `Sources/ShimaCore/AppState.swift` | modify | 9 | `live`, `nowPlaying`, `spotifyAvailability`, `content` |
| `Sources/ShimaCore/SpotifyRequestGate.swift` | create | 10 | coalescing, sequence/pid tickets, `SpotifyScriptError` |
| `Sources/ShimaCore/IslandLayout.swift` | modify | 11 | `liveWingWidth`, idle frame, metrics and hot rect as functions of `(notch, live)` |
| `Sources/ShimaCore/NowPlayingLayout.swift` | create | 11 | open-island and wing geometry (island-local, y-down) |
| `Sources/ShimaCore/HoverMachine.swift`, `HoverController.swift` | modify | 12 | `.idleGeometryChanged` input, `idleGeometryChanged()` |
| `Sources/Shima/Log.swift` | modify | 13 | categories `spotify`, `artwork`, `eq`, `focus` |
| `Sources/Shima/IslandMedia.swift` | create | 13 | `@Observable` artwork image and the equalizer freeze flag |
| `Sources/Shima/SpotifyService.swift` | create | 13, 17 | picks fake or real client, fake control channel, event funnel and logging |
| `Sources/Shima/AppDelegate.swift` | modify | 13 | wires the service to the island, logs `app became active` |
| `Sources/Shima/IslandPanelController.swift` | modify | 11, 14, 18-21 | desired/applied live, live frame and hot rect, open hook, commands |
| `Sources/Shima/IslandView.swift` | modify | 14, 19-21 | live collapsed shape, wings, open-island content |
| `scripts/shima-windows.swift`, `scripts/verify-alignment.sh` | modify | 15 | `--live`, `--expanded`, `--menus`, status-item gap check |
| `scripts/verify-live-hover.sh` | create | 15 | live-state hover sequences A-H with assertions |
| `Sources/Shima/SpotifyScripting.swift` | create | 16 | serial queue, snapshot and commands, error mapping |
| `Sources/Shima/SpotifyAppleEventClient.swift` | create | 16 | `SpotifyClient` over `SpotifyScripting` with the gate |
| `Sources/Shima/SpotifyObservers.swift` | create | 17 | `PlaybackStateChanged` (`.deliverImmediately`) and workspace launch/terminate |
| `scripts/run.sh` | modify | 17 | refuse an ad-hoc real-mode build while Spotify runs |
| `Sources/Shima/ArtworkCache.swift` | create | 18 | ephemeral session, `NSCache` (10), 176 px downsample, stale drop |
| `Sources/Shima/WingsView.swift` | create | 19 | mini artwork and equalizer in the collapsed live wings |
| `Sources/Shima/NowPlayingView.swift` | create | 20, 21 | open-island content, progress, `TimelineView`, buttons |
| `Sources/Shima/ClickHostingView.swift` | create | 21 | `NSHostingView` subclass with `acceptsFirstMouse` true |
| `scripts/verify-focus.sh` | modify | 22 | `--clicks`: real button clicks, frontmost and `NSApp.isActive` checks |
| `scripts/verify-idle.sh` | modify | 23 | strict mode, `--playing` A/B, static check with allowlist |
| `Tests/ShimaCoreTests/NowPlayingTests.swift` ... `SpotifyRequestGateTests.swift`, `NowPlayingLayoutTests.swift` | create | 6-11 | tests |
| `Tests/ShimaCoreTests/IslandLayoutTests.swift`, `HoverMachineTests.swift`, `HoverControllerTests.swift` | modify | 11, 12 | tests |
| `docs/superpowers/m1-acceptance.md` | create | 25 | acceptance record |

## Who can do what in parallel

- **PURE, parallel-safe (second engineer, own worktree):** Tasks 6-12 touch only `Sources/ShimaCore` and `Tests/ShimaCoreTests` (Task 11 also edits three call sites in `IslandPanelController.swift` to pass `live: false`, a mechanical change that merges cleanly because the spikes revert all their `Sources/Shima` edits). Internal order: 6 → 7 → 8 → 9; 10, 11 (needs 6 for `SpotifyCommand`) and 12 are independent. **Wait for spike notes before:** Task 7 (Spikes 1-2: payload keys, units, track id form, artwork URL form), Task 9 (Spike 1: notification rate), Task 12 (Spike 3: machine design confirmed).
- **SPIKES (main engineer, with the user for HUMAN steps):** Tasks 1-5, sequential, in the main worktree. Tasks 1 and 2's HUMAN parts can be done in one sitting with the user.
- **GLUE and SCRIPT, sequential (main engineer):** Tasks 13-24 share `IslandPanelController.swift`, `IslandView.swift`, `SpotifyService.swift` and `AppDelegate.swift`; run them one at a time after Tasks 6-12 are merged.

---

### Task 1: Spike: the `com.spotify.client.PlaybackStateChanged` payload, rate and seeks (HUMAN)

Settles 8.5's first unverified items: what the broadcast carries, how often it fires while playing, whether seeks post it, and the order of launch/quit notifications versus broadcasts. No product code. The observer script is thrown away.

**Files:**
- Create (temporary, deleted at end of task): `scripts/spike-spotify-notifications.swift`
- Create: `docs/superpowers/spikes/2026-11-21-m1-spikes.md`

**Interfaces:**
- Produces, in the notes: `payloadKeys` (key, value type, unit for each), `payloadComplete` (true when `Player State`, `Track ID`, `Name`, `Artist` and `Playback Position` are all present while playing), `trackIDForm` (e.g. `spotify:track:<22 chars>`), `ratePlaying` (broadcasts per minute while playing untouched), `seekPosts` (yes/no), `quitOrder` (sequence of broadcasts and `didTerminate`). Tasks 7, 8 and 9 read these.

- [ ] **Step 1: Write the throwaway observer**

`scripts/spike-spotify-notifications.swift`:
```swift
import AppKit
// Throwaway (Task 1). Prints Spotify's playback broadcast and Spotify's launch/quit, with seconds since start.
let start = Date()
func out(_ s: String) { print(String(format: "%8.3f ", Date().timeIntervalSince(start)) + s); fflush(stdout) }
DistributedNotificationCenter.default().addObserver(
    forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { n in
    out("PlaybackStateChanged object=\(String(describing: n.object))")
    for (k, v) in (n.userInfo ?? [:]).sorted(by: { "\($0.key)" < "\($1.key)" }) {
        out("    \(k) = \(v) [\(type(of: v))]")
    }
}
for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
    NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { n in
        guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.spotify.client" else { return }
        out("\(name.rawValue) pid=\(app.processIdentifier)")
    }
}
out("observing (Ctrl-C to stop)")
RunLoop.main.run()
```
It only listens. It never sends anything to Spotify.

- [ ] **Step 2: Start the observer**

Run (Spotify quit, if possible: ask the user to quit it first): `swift scripts/spike-spotify-notifications.swift > .build/spike1.log 2>&1 &`
Expected: `.build/spike1.log` contains `observing (Ctrl-C to stop)` within about 2 s.
Between user steps, mark the log: `echo "--- step N <what>" >> .build/spike1.log`.

- [ ] **Step 3: HUMAN checklist (the user does each step and says "done")**

Tell the user: "Mute Spotify (its volume slider at 0) and turn on a Private Session (profile menu, Private session) before pressing play. Nothing here sends commands to Spotify; you drive it by hand."
1. Launch Spotify from the Dock.
2. Turn on Private Session, mute, play any track.
3. Leave it playing, untouched, for 60 s (mark start and end).
4. Pause. Wait 5 s. Play.
5. Next track. Previous track.
6. Seek by dragging Spotify's progress bar, twice, 10 s apart.
7. Seek with the keyboard (Shift-Right in Spotify), twice.
8. Change Spotify's volume slider (still near 0).
9. If an ad plays at any point, say so (free tier).
10. Quit Spotify (Cmd-Q) while playing.

- [ ] **Step 4: Stop and analyse**

Run: `kill %1` (or `pkill -f spike-spotify-notifications`). From `.build/spike1.log` record:
- every key, its Swift type, and the unit of `Duration` and `Playback Position` (compare with the track's real length);
- `payloadComplete`; `trackIDForm`; what `Player State` values occur (`Playing`, `Paused`, `Stopped`, others);
- `ratePlaying`: broadcasts between the step 3 markers, per minute;
- `seekPosts`: whether steps 6 and 7 produced a broadcast;
- whether step 8 posted;
- `quitOrder`: broadcasts and `didTerminate` around step 10, in order, and whether a `Stopped` broadcast arrives after `didTerminate`;
- launch order: `didLaunch` versus the first broadcast.
Do not copy track titles or artist names into the notes; record keys, types, units and counts only.

- [ ] **Step 5: Record the decisions**

Create `docs/superpowers/spikes/2026-11-21-m1-spikes.md` with `# M1 spike notes` and `## Spike 1: PlaybackStateChanged` (date, Spotify version from `/Applications/Spotify.app/Contents/Info.plist` `CFBundleShortVersionString`, macOS version, the table from Step 4). Decision rules, each written down with its outcome:
- `payloadComplete = true` → Task 7 parses the payload; Task 9 refreshes (Apple Events) only for the artwork URL, once per track. `false` → Task 7 parses what is there; Task 9's `!hasDisplayFields` rule refreshes on every broadcast (already in Task 9; note the expected Apple Event rate = `ratePlaying`).
- `ratePlaying` above 6 per minute → add to Task 9: the coordinator skips writing `state.nowPlaying` when only `position`/`positionDate` changed and `state.mode == .collapsed` (test `positionOnlyUpdateWhileCollapsedIsSkipped`). Otherwise no change.
- `seekPosts = no` → no code change (the position re-syncs on island open, 8.2); note it for criterion 5.
- Units differ from the Task 7 test dictionary (`Duration` ms, `Playback Position` s) → update the Task 7 test and parser to the recorded units.
- A `Stopped` broadcast after `didTerminate` → confirms Task 8's `readingWhileNotRunningIsIgnored` rule. A broadcast before `didLaunch` → add to Task 17: a broadcast while not running also posts `.launched` first (record it; default is to ignore).

- [ ] **Step 6: Remove the script, commit the notes**

Run: `rm scripts/spike-spotify-notifications.swift && git status --short`
Expected: only `?? docs/superpowers/spikes/2026-11-21-m1-spikes.md`.
```bash
git add docs/superpowers/spikes/2026-11-21-m1-spikes.md
git commit -m "Spike Spotify's PlaybackStateChanged payload, rate and seeks"
```

---

### Task 2: Spike: raw Apple Events to Spotify by pid; a dead pid returns -600 and launches nothing

Settles: which descriptors return the player state, position and current-track fields (including the artwork URL and the track id form), whether one `pALL` request returns the whole track record, the units, the Automation prompt with the stable identity, and the proof that an event to a dead pid returns -600 without launching Spotify. Keeps three things that later tasks build on: the signing change in `bundle.sh` (so the Automation grant goes to the stable identity, not to the terminal), `scripts/drive.swift`, and `Sources/Shima/SpotifyAppleEvents.swift`.

**Files:**
- Modify (kept): `scripts/bundle.sh`
- Create (kept): `scripts/drive.swift`, `Sources/Shima/SpotifyAppleEvents.swift`
- Create (temporary): `scripts/spike-ae-deadpid.swift`, `Sources/Shima/Spike.swift`, a temporary call in `AppDelegate.swift`
- Modify: `docs/superpowers/spikes/2026-11-21-m1-spikes.md`

**Interfaces:**
- Produces:
  - `bundle.sh`: `SHIMA_SIGN_ID` (default `-`, ad-hoc), `codesign --force --timestamp=none -s "$SIGN_ID"`, Info.plist `NSAppleEventsUsageDescription`. Last line stays `Built dist/Shima.app`.
  - `scripts/drive.swift`: steps `move X Y`, `click X Y` (moves, waits 150 ms, then down/up), `sleep MS`, `key esc`, `fake CMD` (posts distributed notification `local.shima.fake-spotify` with `object = CMD`, `deliverImmediately: true`). Prints `t=<ms> <step>` per step.
  - `enum SpotifyAppleEvents` (in Shima; synchronous, must never run on the main thread):
    - `static let timeout: TimeInterval = 2`
    - `static func code(_ s: String) -> FourCharCode` (four ASCII chars, big-endian)
    - `static func property(_ code: String, of container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor` (object specifier: `want`=`prop`, `form`=`prop`, `seld`=type `code`, `from`=container, coerced to `typeObjectSpecifier`)
    - `static func get(_ specifier: NSAppleEventDescriptor, pid: pid_t) throws -> NSAppleEventDescriptor` (event `core`/`getd`, direct object `----`, `sendEvent(options: [.waitForReply, .neverInteract], timeout: timeout)`; throws `NSError(domain: NSOSStatusErrorDomain, code:)` for a send failure or a non-zero `errn` in the reply; returns the reply's `----`)
    - `static func command(eventClass: String, id: String, pid: pid_t) throws` (e.g. `spfy`/`PlPs`)
  - Notes: `snapshotStrategy = pALL | perProperty`, `stateCodes` (playing/paused/stopped enum codes, expected `kPSP`/`kPSp`/`kPSS`), `durationUnit`, `positionUnit`, `scriptTrackIDForm` (same as `trackIDForm`?), `artworkURLForm`, `deadPidCode`, `promptBehavior`, `grantSurvivesRebuild`.

- [ ] **Step 1: `bundle.sh` signing and usage string (kept)**

In `scripts/bundle.sh`: after `cd`, add `SIGN_ID="${SHIMA_SIGN_ID:--}"`. Add to the Info.plist dict:
```xml
    <key>NSAppleEventsUsageDescription</key><string>shima shows what Spotify is playing and sends it play, pause, next and previous when you click the island's buttons.</string>
```
Replace the two `codesign` lines and the echo with:
```bash
codesign --force --timestamp=none -s "$SIGN_ID" "$APP/Contents/MacOS/shimactl"
codesign --force --timestamp=none -s "$SIGN_ID" "$APP"
echo "signed with: $SIGN_ID"
echo "Built $APP"
```
`--timestamp=none` keeps codesign from contacting Apple's timestamp server (section 2: the only network request is artwork).
Run: `scripts/bundle.sh | tail -2 && codesign -dr - dist/Shima.app 2>&1 | tail -1`
Expected: `signed with: -`, `Built dist/Shima.app`, and `designated => cdhash H"…"` (ad-hoc, unchanged behavior).

- [ ] **Step 2: `scripts/drive.swift` (kept)**

```swift
import AppKit
import CoreGraphics
// Synthetic input for verification. Usage:
//   swift scripts/drive.swift "move 735 16; sleep 500; click 786.5 128; fake playing; key esc"
// Coordinates are global top-left CG points (as printed by scripts/shima-windows.swift).
// `fake CMD` posts the distributed notification local.shima.fake-spotify (object CMD), read only by shima in fake mode.
let start = Date()
func stamp(_ s: String) { print(String(format: "t=%6.0fms ", Date().timeIntervalSince(start) * 1000) + s); fflush(stdout) }
func mouse(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func wait(_ ms: Double) { RunLoop.current.run(until: Date().addingTimeInterval(ms / 1000)) }
for raw in CommandLine.arguments.dropFirst().joined(separator: ";").split(separator: ";") {
    let w = raw.split(separator: " ").map(String.init)
    guard let op = w.first else { continue }
    let n = w.dropFirst().compactMap(Double.init)
    stamp(w.joined(separator: " "))
    switch op {
    case "move": mouse(.mouseMoved, CGPoint(x: n[0], y: n[1]))
    case "click":
        let p = CGPoint(x: n[0], y: n[1])
        mouse(.mouseMoved, p); wait(150); mouse(.leftMouseDown, p); wait(60); mouse(.leftMouseUp, p)
    case "sleep": wait(n[0])
    case "key" where w.count > 1 && w[1] == "esc":
        for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap) }
    case "fake" where w.count > 1:
        DistributedNotificationCenter.default().postNotificationName(
            .init("local.shima.fake-spotify"), object: w[1], userInfo: nil, deliverImmediately: true)
        wait(5)
    default: stamp("unknown step: \(w.joined(separator: " "))"); exit(2)
    }
}
```
Run: `swift scripts/drive.swift "move 735 400; sleep 100; move 735 401"`
Expected: three `t=…ms` lines and the pointer ends at the bottom-centre area; exit 0.

- [ ] **Step 3: `SpotifyAppleEvents.swift` (kept) and the dead-pid proof (AUTOMATED)**

Implement `SpotifyAppleEvents` per the Interfaces block (use `AEReturnID(kAutoGenerateReturnID)` and `AETransactionID(kAnyTransactionID)`; `import Foundation` and `import CoreServices`). Add `dispatchPrecondition(condition: .notOnQueue(.main))` at the top of `get` and `command`.

Write the throwaway `scripts/spike-ae-deadpid.swift`: it starts `/usr/bin/true` with `Process`, waits for it to exit, then sends `core`/`getd` for property `pPlS` to that pid using the same descriptor construction, and prints `dead pid <pid>: code=<NSError code>` (or `UNEXPECTED reply`).
First check Spotify is quit: `pgrep -x Spotify` (if it prints a pid, ask the user to quit Spotify; never quit it from a script). Then run:
`pgrep -x Spotify; swift scripts/spike-ae-deadpid.swift; sleep 5; pgrep -x Spotify; echo "exit $?"`
Expected: `dead pid <n>: code=-600`, no pid printed by either `pgrep`, and `exit 1` from the last `pgrep`. Record `deadPidCode`.
**Stop rule:** if Spotify appears in `pgrep` at any point, stop M1 and report to the user.

- [ ] **Step 4: Temporary in-app spike (`SHIMA_SPIKE=ae`)**

`Spike.swift` adds `enum Spike { @MainActor static func startAppleEventSpike() }`, called from `applicationDidFinishLaunching` when `SHIMA_SPIKE=ae`. It:
- looks up `NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first { !$0.isTerminated }`; with none, logs `spike ae: Spotify not running, no event sent` and does nothing else;
- otherwise remembers that pid and, on a private serial `DispatchQueue`, reads and logs (via `Log.display`, `privacy: .public`) each of: `pPlS`, `pPos`, `pTrk` with `pALL`, and individually `pnam`, `pArt`, `pAlb`, `pDur`, `aUrl`, `ID  ` of `pTrk`. Each log line: `spike ae <code> type=<descriptorType as 4 chars> value=<stringValue or doubleValue or enumCodeValue as 4 chars> ms=<elapsed>` or `spike ae <code> error=<code> ms=<elapsed>`. For the `pALL` record, log each key (4 chars) and value type. Do not log the title or artist values themselves; log `value=<n chars>` for text.
- observes `local.shima.fake-spotify` (selector API, `suspensionBehavior: .deliverImmediately`) and handles objects: `ae-read` (repeat the reads), `ae-playpause`, `ae-next`, `ae-prev` (send `spfy`/`PlPs`, `spfy`/`Next`, `spfy`/`Prev`, log the result code), `ae-stale` (send `getd pPlS` to the remembered pid even if Spotify quit; log the code).

Run: `swift build 2>&1 | tail -1`. Expected: `Build complete!`.

- [ ] **Step 5: Not running (AUTOMATED)**

With Spotify quit: `SHIMA_SPIKE=ae scripts/run.sh && sleep 3 && /usr/bin/log show --last 10s --predicate 'subsystem == "local.shima"' | grep "spike ae"; pgrep -x Spotify; echo "exit $?"`
Expected: `spike ae: Spotify not running, no event sent`, no Spotify pid, `exit 1`.

- [ ] **Step 6: Running (HUMAN)**

With the user present. Start `scripts/watch-hover.sh` in a second terminal (it streams the whole `local.shima` subsystem).
1. The user launches Spotify, turns on Private Session and mutes it, and plays a track.
2. The controller runs `SHIMA_SIGN_ID='Apple Development: jpatrickzephyr@gmail.com (<cert-id>)' SHIMA_SPIKE=ae scripts/run.sh`. **HUMAN:** the "codesign wants to access key" dialog appears; the user enters the login password and chooses Allow (or Always Allow, their choice).
3. **HUMAN:** the Automation prompt "“Shima” wants access to control “Spotify”" appears; the user clicks Allow. Record whether the first events timed out (`error=-1712`) while the prompt was up, and how long the prompt blocked.
4. The controller checks `codesign -dr - dist/Shima.app 2>&1 | tail -1` shows `designated => identifier "local.shima" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: jpatrickzephyr@gmail.com (<cert-id>)" …` (no `cdhash`).
5. The user pauses in Spotify, then runs `swift scripts/drive.swift "fake ae-read"`; then plays again and runs it again (records the paused and playing enum codes).
6. The user runs, one at a time, watching Spotify: `swift scripts/drive.swift "fake ae-next"`, `"fake ae-prev"`, `"fake ae-playpause"` (twice). They report whether Spotify followed each command.
7. Persistence: the controller re-runs step 2's command (a rebuild with the same identity). Expected: no Automation prompt; the reads succeed. Record `grantSurvivesRebuild`.
8. The user quits Spotify. The controller runs `swift scripts/drive.swift "fake ae-stale"; sleep 5; pgrep -x Spotify; echo "exit $?"`. Expected: `spike ae pPlS error=-600` (or `-609`), no Spotify pid, `exit 1`.

- [ ] **Step 7: Record the decisions**

Add `## Spike 2: raw Apple Events by pid` with the table of codes, types, units and timings. Decision rules:
- `pALL` on `pTrk` returns a record with `pnam`, `pArt`, `pAlb`, `pDur`, `aUrl`, `ID  ` → `snapshotStrategy = pALL` (Task 16 sends 3 events per snapshot: `pPlS`, `pPos`, `pALL of pTrk`). Otherwise `perProperty` (8 events).
- `durationUnit`/`positionUnit` → Task 16's conversion (expected: duration ms, position s).
- `scriptTrackIDForm` differs from Spike 1's `trackIDForm` → add `SpotifyReading.normalizedTrackID(_:)` to Task 7 with a test mapping both forms to one, used by both parsers.
- `artworkURLForm` is not `https://…` → Task 7's `artworkURL(from:)` rewrites `http://i.scdn.co/` to `https://i.scdn.co/` (add test `httpScdnIsUpgraded`); any other scheme stays rejected.
- `deadPidCode` is not -600/-609, or Spotify ever launched → stop and report to the user.
- `grantSurvivesRebuild = no` → stop and report (criterion 8 cannot pass; the signing approach must be revisited with the user).

- [ ] **Step 8: Remove spike code, keep the rest, commit**

Run: `git checkout Sources/Shima/AppDelegate.swift && rm Sources/Shima/Spike.swift scripts/spike-ae-deadpid.swift && swift build 2>&1 | tail -1 && git status --short`
Expected: `Build complete!`; status shows `M scripts/bundle.sh`, `?? scripts/drive.swift`, `?? Sources/Shima/SpotifyAppleEvents.swift`, `M docs/superpowers/spikes/2026-11-21-m1-spikes.md`.
```bash
git add scripts/bundle.sh scripts/drive.swift Sources/Shima/SpotifyAppleEvents.swift docs/superpowers/spikes/2026-11-21-m1-spikes.md
git commit -m "Spike raw Apple Events to Spotify by pid; sign with SHIMA_SIGN_ID; add drive.swift"
```

---

### Task 3: Spike: live-frame change during hover (AUTOMATED, plus a short HUMAN glance)

8.5's last unverified item. The idle frame grows from 179 to 245 pt when Spotify starts and shrinks when it stops, while the hover machine may be in any phase. This proves, with the real `HoverMachine` plus throwaway glue, that there is exactly one frame change per transition and no `collapsing` loop, before Task 12 pins the design in tests. Keeps `scripts/with-log.sh`.

**Files:**
- Create (kept): `scripts/with-log.sh`
- Temporary edits (reverted at end): `Sources/ShimaCore/HoverMachine.swift`, `Sources/ShimaCore/HoverController.swift`, `Sources/ShimaCore/AppState.swift`, `Sources/Shima/IslandPanelController.swift`, `Sources/Shima/IslandView.swift`
- Modify: `docs/superpowers/spikes/2026-11-21-m1-spikes.md`

**Interfaces:**
- Produces: `scripts/with-log.sh OUT -- CMD…` (streams `subsystem == "local.shima"` at debug level to OUT while CMD runs; returns CMD's exit code). Notes: `liveFrameStrategy = growThenAnimate | variantA | variantB | constantWidth` and the per-case table. Tasks 12, 14 and 15 read it.

- [ ] **Step 1: `scripts/with-log.sh` (kept)**

```bash
#!/usr/bin/env bash
# Usage: scripts/with-log.sh OUT -- CMD...   Captures shima's unified log (debug level) while CMD runs.
set -uo pipefail
out="$1"; shift; [[ "${1:-}" == "--" ]] && shift
/usr/bin/log stream --level debug --style compact --predicate 'subsystem == "local.shima"' > "$out" 2>&1 &
lp=$!
sleep 1.5
"$@"; rc=$?
sleep 1
kill "$lp" 2>/dev/null; wait "$lp" 2>/dev/null
exit "$rc"
```
`chmod +x scripts/with-log.sh`.

- [ ] **Step 2: Throwaway live glue**

- `HoverMachine`: add `case idleGeometryChanged` to `HoverInput` and, right after the `reset` case, `case (_, .idleGeometryChanged): return panelLarge ? [] : [.shrinkPanel]`. `HoverController`: `public func idleGeometryChanged() { handle(.idleGeometryChanged) }`. Timing: `HoverTiming(dwell: .milliseconds(Int(env["SHIMA_SPIKE_DWELL_MS"] ?? "80")!), leaveDebounce: .milliseconds(300))`.
- `AppState`: `public var live = false` (applied wing state).
- `IslandPanelController`: `desiredLive`; a `local.shima.fake-spotify` observer (`.deliverImmediately`) mapping `playing` → `desiredLive = true`, `paused` → `false`, then `hover.idleGeometryChanged()`. `.shrinkPanel` → if turning on: `setFrame(idle(live: true))`, then `withAnimation(spring) { state.live = true }`; if turning off: snap `state.live = false` (disabled-animation transaction), then `setFrame(idle(live: false))`; else re-apply. `idle(live:)` is `live ? notch.insetBy(dx: -33, dy: 0) : notch`. The idle hot rect is `idle(live: state.live)` in panel-local coordinates. The `frame idle` log line gets ` live=<bool>` at the end.
- `IslandView`: collapsed metrics width `notch.width + (state.live ? 66 : 0)`.

Run: `swift build 2>&1 | tail -1`. Expected: `Build complete!`.

- [ ] **Step 3: Run the cases**

Launch: `SHIMA_DEBUG=1 scripts/run.sh` (the red tint makes the wings visible), pointer away. For each case: reset with `swift scripts/drive.swift "fake paused; move 735 400; sleep 1500"`, then
`scripts/with-log.sh .build/s3-<case>.log -- swift scripts/drive.swift "<steps>"` and count `frame` and `hover` lines.

| Case | Steps | Pass |
|---|---|---|
| 1 idle toggles | `fake playing; sleep 400; fake paused; sleep 400` ×5 | 10 `frame idle` lines alternating `w=245.0`/`w=179.0`; no `hover` lines |
| 2 open, toggle | `move 735 16; sleep 700; fake playing; sleep 400; move 735 400; sleep 1500` | `frame expanded` ×1; no frame line at the toggle; one `frame idle … w=245.0` after `collapsing -> collapsed` |
| 3 dwelling (relaunch with `SHIMA_SPIKE_DWELL_MS=1500`) | `move 735 16; sleep 300; fake playing; sleep 300; fake paused; sleep 1500; move 735 400; sleep 1500` | one `frame idle` per toggle, phase stays `dwelling` through both, then `dwelling -> expanded` with one `frame expanded` |
| 4 pointer on the wing, live off (dwell 1500) | `fake playing; sleep 500; move 630 16; sleep 300; fake paused; sleep 500` | `frame idle … w=179.0`, then `dwelling -> collapsed`, no `expanded` |
| 5 live on next to the notch (dwell 80) | `move 630 16; sleep 500; fake playing; sleep 800` | `frame idle … w=245.0`, then `collapsed -> dwelling -> expanded` (expected: the pointer is now on the island) |
| 6 mid-expand | `move 735 16; sleep 150; fake playing; sleep 600; move 735 400; sleep 1500` | no frame line at the toggle; one `frame idle … w=245.0` after the collapse |
| 7 mid-collapse re-entry | `fake playing; sleep 400; move 735 16; sleep 700; move 735 400; sleep 400; move 735 16; sleep 20; fake paused; sleep 700; move 735 400; sleep 1500` | `collapsing -> dwelling -> expanded` without a `frame` line; the only later frame line is one `frame idle … w=179.0` |
| 8 rapid toggles | `fake playing; sleep 30; fake paused; sleep 30` ×10 | 20 `frame idle` lines, last `w=179.0`, no `hover` lines |
| 9 wiggle while live | `fake playing; sleep 400; move 735 16; sleep 700;` then ×20 `move 735 178; sleep 50; move 735 165; sleep 50;` then `move 735 400; sleep 1500` | only `expanded <-> leaving` while wiggling; exactly one `-> collapsing` |

Also count `hover` lines that repeat a transition with no pointer step between them (re-sent `mouseEntered`): expected none.

- [ ] **Step 4: HUMAN glance**

Ask the user to watch the notch while the controller runs cases 1 and 2 again (about 10 s, pointer away for case 1). Question: "Did the wings ever flash, jump, appear doubled, or show a box, as they appeared or disappeared?" Record the answer.

- [ ] **Step 5: Record the decision**

Add `## Spike 3: live-frame change during hover` with the case table (counts per case) and the HUMAN answer. Decision rules:
- All pass and no flicker → `liveFrameStrategy = growThenAnimate`: Task 12 implements exactly the throwaway rule; Task 14 uses the same order (grow the frame, then animate the wings in; snap the wings out, then shrink).
- Flicker on live start only → try (a) `setFrame(_, display: false)` followed by `contentView?.layoutSubtreeIfNeeded(); contentView?.displayIfNeeded()`; (b) start the wings animation on the next run-loop turn (`DispatchQueue.main.async`). Record which passes as `variantA`/`variantB`; Task 14 uses it.
- Extra frame lines or a `collapsing` loop → the machine rule is wrong: write the failing case as a new Task 12 test first, change the rule in Task 12's table, and rerun this spike before Task 13.
- Nothing above fixes flicker → the last resort (8.5) is a constant-width idle frame (notch plus wings, transparent when not live) with only the hot rect changing. It breaks M0 criterion 1 and depends on click-through over menu items, so **stop and ask the user** before choosing it.

- [ ] **Step 6: Revert the throwaway code, commit**

Run: `git checkout Sources/ && swift build 2>&1 | tail -1 && swift test 2>&1 | tail -1 && git status --short`
Expected: `Build complete!`, `✔ Test run with 59 tests in 7 suites passed…`, status shows `?? scripts/with-log.sh` and `M docs/superpowers/spikes/2026-11-21-m1-spikes.md`.
```bash
git add scripts/with-log.sh docs/superpowers/spikes/2026-11-21-m1-spikes.md
git commit -m "Spike live-frame change during hover; add with-log.sh"
```

---

### Task 4: Spike: button clicks on the non-key panel do not activate the app (AUTOMATED, plus a HUMAN cursor glance)

8.2 "Clicks" and 8.5: does a SwiftUI `Button` inside the non-activating, never-key panel act on the first click, with `NSApp.isActive` false and the frontmost app unchanged? Throwaway code only.

**Files:**
- Temporary edits (reverted): `Sources/Shima/IslandPanelController.swift`, `Sources/Shima/IslandView.swift`, `Sources/Shima/AppDelegate.swift`
- Modify: `docs/superpowers/spikes/2026-11-21-m1-spikes.md`

**Interfaces:**
- Produces: notes decision `clickStrategy = buttonFirstMouse | gestureFirstMouse | appKitHitTest`. Task 21 reads it.

- [ ] **Step 1: Throwaway click glue**

- A generic `final class SpikeHostingView<Content: View>: NSHostingView<Content>` whose `acceptsFirstMouse(for:)` returns `env["SHIMA_SPIKE_FIRSTMOUSE"] != "0"`; `IslandPanelController` uses it instead of `NSHostingView`.
- In `IslandView`, while expanded, a 32x32 white circle at island-local `(215, 112)` (y-down; screen centre `786.5 128`) that is a `Button(action:)` with `.buttonStyle(.plain)`, or, with `SHIMA_SPIKE_TAP=gesture`, a view with `.onTapGesture`. The action logs `spike tap active=\(NSApp.isActive) key=\(panel.isKeyWindow) main=\(panel.isMainWindow)` (`Log.display`, public).
- `AppDelegate`: observe `NSApplication.didBecomeActiveNotification` and log `app became active` (error level).

Run: `swift build 2>&1 | tail -1`. Expected: `Build complete!`.

- [ ] **Step 2: Run the variants**

Click into a Terminal or TextEdit window first, so it is frontmost. For each variant (`SHIMA_SPIKE_FIRSTMOUSE=1`, `=0`, and `SHIMA_SPIKE_TAP=gesture` with first mouse on), relaunch with `scripts/run.sh` plus the variables, then:
`before="$(lsappinfo info -only name "$(lsappinfo front)")"; scripts/with-log.sh .build/s4.log -- swift scripts/drive.swift "move 735 400; sleep 400; move 735 16; sleep 600; click 786.5 128; sleep 400; click 786.5 128; sleep 400; click 600 60; sleep 300; move 735 400; sleep 1200"; after="$(lsappinfo info -only name "$(lsappinfo front)")"; echo "$before | $after"; grep -E "spike tap|became active" .build/s4.log`
Record per variant: taps logged for the two button clicks (want 2), their `active=`/`key=` values (want false), taps for the artwork click (want 0), `app became active` (want none), and whether `before == after`.

- [ ] **Step 3: HUMAN glance**

The user hovers the island and moves over the white circle: does the cursor stay the arrow? Does the press look right (no system bezel)? Record.

- [ ] **Step 4: Record the decision, revert**

Add `## Spike 4: clicks on the non-key panel`. Decision rule: the first variant (in the order button with first mouse, gesture with first mouse) with 2 taps for 2 clicks, `active=false key=false`, 0 taps on the artwork, no `app became active` and unchanged frontmost wins. If neither passes: `clickStrategy = appKitHitTest` (Task 21: `ClickHostingView.mouseDown` converts the point to island-local y-down coordinates, hit-tests `NowPlayingLayout.controlRect(_:)` and calls the action; the SwiftUI buttons become plain images). Record also what `FIRSTMOUSE=0` did (expected: the first click is swallowed), to justify `acceptsFirstMouse`.
Run: `git checkout Sources/ && swift build 2>&1 | tail -1`. Expected: `Build complete!`.
```bash
git add docs/superpowers/spikes/2026-11-21-m1-spikes.md
git commit -m "Spike button clicks on the non-key panel"
```

---

### Task 5: Spike: Core Animation equalizer CPU A/B (AUTOMATED)

8.4 equalizer and 8.5 "whether a frozen Core Animation layer costs nothing". Builds the real `EqualizerView` (kept) with the lifecycle rules from 8.4, shows it on a throwaway panel at the right-wing position, and measures Shima and WindowServer CPU for animating, frozen and hidden.

**Files:**
- Create (kept): `Sources/Shima/EqualizerView.swift`
- Create (temporary): `Sources/Shima/Spike.swift`, a temporary call in `AppDelegate.swift`, `scripts/spike-eq-ab.sh`
- Modify: `docs/superpowers/spikes/2026-11-21-m1-spikes.md`

**Interfaces:**
- Produces:
  - `final class EqualizerNSView: NSView` with `var animating: Bool` (idempotent; `didSet` re-applies), `static var tint: NSColor` (`#1ED760`), `static var frameRate: Float?` (from this spike; `nil` = display rate).
  - `struct EqualizerView: NSViewRepresentable { let animating: Bool }` (`makeNSView` once, `updateNSView` sets `animating`).
  - Notes: `eqFrameRate` and the measured table. Tasks 19 and 23 read them.

- [ ] **Step 1: `EqualizerView.swift` (kept)**

Geometry from 8.2 and the mockup `.wave`: 4 bars, `2.5 x 14` pt, gap 2 pt (16 pt in all), corner radius 1.25, centred vertically, colour `EqualizerNSView.tint`. Each bar is a sublayer with `anchorPoint (0.5, 0.5)` and rest transform `CATransform3DMakeScale(1, 0.25, 1)`.
Animation per bar (key `"eq"`): `CABasicAnimation(keyPath: "transform.scale.y")`, `fromValue 0.22`, `toValue 1.0`, `autoreverses = true`, `repeatCount = .infinity`, `timingFunction = .easeInEaseOut`, durations `[0.9, 0.7, 1.1, 0.8]`, `timeOffset` `[0, 0.3, 0.5, 0.2]`, `isRemovedOnCompletion = false`, and `preferredFrameRateRange = CAFrameRateRange(minimum: r, maximum: r, preferred: r)` when `frameRate` is set.
Rules (8.4):
- `wantsLayer = true` in `init`; bars created once.
- `effective = animating && window != nil && window!.occlusionState.contains(.visible)`. `apply()` compares `effective` with the current state and does nothing when equal (idempotent). Turning on: add the animation to every bar that has none for `"eq"`. Turning off: inside `CATransaction.begin(); CATransaction.setDisableActions(true)`, remove `"eq"` and set the rest transform; `commit()`.
- `viewDidMoveToWindow()`: (re)subscribe to `NSWindow.didChangeOcclusionStateNotification` for the new window, then `apply()`. The occlusion callback calls `apply()`. This re-adds the animations after `orderOut`/`orderFront` and pauses them while the display sleeps.
- Each real state change logs `eq animating anims=<total animation count over the bars>` or `eq frozen anims=0` (`Log.eq` will exist after Task 13; for now use `Logger(subsystem: "local.shima", category: "eq")` inline).
- `repeatCount` appears only in this file (Task 23's allowlist).

- [ ] **Step 2: Throwaway spike panel**

`Spike.swift`: `SHIMA_SPIKE=eq` creates a second `NotchPanel` at AppKit `(825, 924, 33, 32)` (the right wing; clear of the status item at 860), black background, with an `EqualizerNSView` centred. It observes `local.shima.fake-spotify` (`.deliverImmediately`): `eq-animating`, `eq-frozen` (set `animating`), `eq-hide` (`orderOut`), `eq-show` (`orderFrontRegardless`), `eq-rate-display`, `eq-rate-30`, `eq-rate-20` (set `frameRate`, then off and on again).
`scripts/spike-eq-ab.sh` (throwaway): measures CPU seconds over a window for Shima and WindowServer with `ps -o time= -p <pid>` (parse `m:ss.cc` as in `verify-idle.sh`), for phases animating / frozen / hidden, 30 s each, two rounds alternating, after a 3 s settle per phase; prints average % per phase for both processes.

- [ ] **Step 3: Measure (keep the pointer still and nothing else animating on screen)**

Run: `swift build 2>&1 | tail -1 && SHIMA_SPIKE=eq scripts/run.sh && sleep 3`, then for each rate (`display`, `30`, `20`): `swift scripts/drive.swift "fake eq-rate-<r>"; scripts/spike-eq-ab.sh`.
Check first that `ps -o time= -p "$(pgrep -x WindowServer)"` prints a value; if it does not, use `top -l 2 -s 30 -pid <ws> -stats cpu | tail -1` per phase instead and say so in the notes.
Also run `sample "$(pgrep -nx Shima)" 3 -file .build/s5-sample.txt` while animating and check that it contains no `__CFRUNLOOP_IS_CALLING_OUT_TO_A_TIMER_CALLBACK_FUNCTION__`.

- [ ] **Step 4: Lifecycle checks**

`scripts/with-log.sh .build/s5.log -- swift scripts/drive.swift "fake eq-animating; sleep 300; fake eq-animating; sleep 300; fake eq-frozen; sleep 300; fake eq-frozen; sleep 300; fake eq-animating; sleep 300; fake eq-hide; sleep 300; fake eq-show; sleep 300"` then `grep "eq " .build/s5.log`.
Expected: `eq animating anims=4`, `eq frozen anims=0`, `eq animating anims=4`, `eq frozen anims=0` (on hide, via occlusion), `eq animating anims=4` (on show). Repeated commands log nothing (idempotent). Ten rapid `eq-animating`/`eq-frozen` pairs never log `anims=8`.

- [ ] **Step 5: Record the decision, clean up**

Add `## Spike 5: equalizer CPU` with the table (rate × phase × process). Decision rules:
- `eqFrameRate` = the highest of display rate, 30, 20 for which Shima animating ≤ 0.1% and WindowServer (animating − frozen) ≤ 1.5% (criterion 7). Set `EqualizerNSView.frameRate` to it in the kept file (`nil` for display rate).
- None meets the budget → keep 20, record the honest numbers, and ask the user before Task 19 (criterion 7 says numbers are reported even if worse).
- Frozen − hidden for WindowServer > 0.1% → record; Task 19 additionally sets the bars' `isHidden = true` while frozen and not live.
Run: `git checkout Sources/Shima/AppDelegate.swift && rm Sources/Shima/Spike.swift scripts/spike-eq-ab.sh && swift build 2>&1 | tail -1 && git status --short`
Expected: `Build complete!`; status `?? Sources/Shima/EqualizerView.swift`, `M docs/…/2026-11-21-m1-spikes.md`.
```bash
git add Sources/Shima/EqualizerView.swift docs/superpowers/spikes/2026-11-21-m1-spikes.md
git commit -m "Spike Core Animation equalizer CPU; add EqualizerView"
```

---

### Task 6: NowPlaying, position(at:) and time formatting (PURE, parallel-safe)

**Files:**
- Create: `Sources/ShimaCore/NowPlaying.swift`
- Test: `Tests/ShimaCoreTests/NowPlayingTests.swift`

**Interfaces:**
- Produces:
```swift
public enum PlaybackState: String, Equatable, Sendable { case playing, paused, stopped }
public enum SpotifyCommand: String, Equatable, Sendable, CaseIterable { case previous, playPause, next }
public struct NowPlaying: Equatable, Sendable {
    public var trackID: String
    public var title: String, artist: String, album: String
    public var artworkURL: URL?
    public var duration: TimeInterval      // seconds; 0 = unknown
    public var position: TimeInterval      // seconds, sampled at positionDate
    public var positionDate: Date
    public var state: PlaybackState
    public init(trackID:title:artist:album:artworkURL:duration:position:positionDate:state:)
    public func position(at date: Date) -> TimeInterval
}
public enum PlaybackTime {
    public static func elapsed(_ seconds: TimeInterval) -> String          // "m:ss" or "h:mm:ss", floor, never negative
    public static func remaining(position: TimeInterval, duration: TimeInterval) -> String  // "-m:ss" of floor(duration) - floor(position), never below 0; "" when duration <= 0
    public static func fraction(position: TimeInterval, duration: TimeInterval) -> Double  // 0...1; 0 when duration <= 0
}
```
`position(at:)`: when `state == .playing`, `position + max(0, date - positionDate)`, clamped to `duration` when `duration > 0`; otherwise `position`. Never below 0.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import ShimaCore

@Suite struct NowPlayingTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    func track(_ state: PlaybackState, position: TimeInterval = 10, duration: TimeInterval = 200) -> NowPlaying {
        NowPlaying(trackID: "spotify:track:a", title: "Song", artist: "Artist", album: "Album",
                   artworkURL: nil, duration: duration, position: position, positionDate: t0, state: state)
    }

    @Test func playingExtrapolates() { #expect(track(.playing).position(at: t0 + 5) == 15) }
    @Test func playingClampsToDuration() { #expect(track(.playing, position: 198).position(at: t0 + 30) == 200) }
    @Test func pausedIsStatic() { #expect(track(.paused).position(at: t0 + 30) == 10) }
    @Test func clockBeforeSampleNeverGoesBack() { #expect(track(.playing).position(at: t0 - 5) == 10) }
    @Test func unknownDurationHasNoUpperClamp() { #expect(track(.playing, duration: 0).position(at: t0 + 500) == 510) }
    @Test func elapsedFormat() {
        #expect(PlaybackTime.elapsed(0) == "0:00")
        #expect(PlaybackTime.elapsed(71.9) == "1:11")
        #expect(PlaybackTime.elapsed(3725) == "1:02:05")
        #expect(PlaybackTime.elapsed(-3) == "0:00")
    }
    @Test func remainingFormat() {
        #expect(PlaybackTime.remaining(position: 71, duration: 200) == "-2:09")
        #expect(PlaybackTime.remaining(position: 250, duration: 200) == "-0:00")
    }
    @Test func unknownDurationShowsNoRemaining() { #expect(PlaybackTime.remaining(position: 10, duration: 0) == "") }
    @Test func fraction() {
        #expect(PlaybackTime.fraction(position: 71, duration: 200) == 0.355)
        #expect(PlaybackTime.fraction(position: 10, duration: 0) == 0)
        #expect(PlaybackTime.fraction(position: 300, duration: 200) == 1)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter NowPlayingTests 2>&1 | tail -3`
Expected: build error `cannot find 'NowPlaying' in scope`.

- [ ] **Step 3: Implement `NowPlaying.swift`** (`import Foundation`).

- [ ] **Step 4: Run to verify they pass**

Run: `swift test 2>&1 | tail -1`
Expected: starts with `✔ Test run with 68 tests in 8 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShimaCore/NowPlaying.swift Tests/ShimaCoreTests/NowPlayingTests.swift
git commit -m "Add NowPlaying with position extrapolation and time formatting"
```

---

### Task 7: SpotifyReading and payload parsing (PURE, parallel-safe; after Spikes 1-2)

**Files:**
- Create: `Sources/ShimaCore/SpotifyReading.swift`
- Test: `Tests/ShimaCoreTests/SpotifyReadingTests.swift`

**Interfaces:**
- Consumes: `PlaybackState` (Task 6); Spike 1 `payloadKeys`/units, Spike 2 `artworkURLForm`, `scriptTrackIDForm`.
- Produces:
```swift
public enum ReadingSource: Equatable, Sendable { case notification, script }
public struct SpotifyReading: Equatable, Sendable {
    public var state: PlaybackState
    public var trackID: String?, title: String?, artist: String?, album: String?
    public var duration: TimeInterval?     // seconds
    public var position: TimeInterval?     // seconds
    public var artworkURL: URL?
    public init(state: PlaybackState, trackID: String? = nil, title: String? = nil, artist: String? = nil,
                album: String? = nil, duration: TimeInterval? = nil, position: TimeInterval? = nil, artworkURL: URL? = nil)
    /// Parses Spotify's PlaybackStateChanged userInfo. nil when "Player State" is missing or unknown.
    public init?(notification userInfo: [AnyHashable: Any])
    /// https only, non-empty; everything else nil.
    public static func artworkURL(from string: String?) -> URL?
    /// trackID, title, artist and position all present.
    public var hasDisplayFields: Bool { get }
}
```
Parsing (keys from Spike 1; the defaults below are the expected ones): `"Player State"` `"Playing"|"Paused"|"Stopped"` → `.playing|.paused|.stopped`; `"Track ID"`, `"Name"`, `"Artist"`, `"Album"` as `String`, empty string → nil; `"Duration"` `NSNumber` in **ms** → seconds; `"Playback Position"` `NSNumber` in **s**. Other keys are ignored. The payload carries no artwork URL.

- [ ] **Step 1: Write the failing tests** (update the dictionary to Spike 1's recorded keys and units if they differ)

```swift
import Foundation
import Testing
@testable import ShimaCore

@Suite struct SpotifyReadingTests {
    let full: [AnyHashable: Any] = [
        "Player State": "Playing", "Track ID": "spotify:track:abc", "Name": "Song", "Artist": "Artist",
        "Album": "Album", "Duration": NSNumber(value: 200_000), "Playback Position": NSNumber(value: 71.5),
        "Has Artwork": true, "Popularity": NSNumber(value: 50)]

    @Test func parsesFullPayload() {
        #expect(SpotifyReading(notification: full) == SpotifyReading(
            state: .playing, trackID: "spotify:track:abc", title: "Song", artist: "Artist", album: "Album",
            duration: 200, position: 71.5, artworkURL: nil))
    }
    @Test func parsesStoppedOnly() {
        #expect(SpotifyReading(notification: ["Player State": "Stopped"]) == SpotifyReading(state: .stopped))
    }
    @Test func parsesPaused() { #expect(SpotifyReading(notification: ["Player State": "Paused"])?.state == .paused) }
    @Test func missingOrUnknownStateIsNil() {
        #expect(SpotifyReading(notification: [:]) == nil)
        #expect(SpotifyReading(notification: ["Player State": "Buffering"]) == nil)
    }
    @Test func emptyStringsAreMissing() {
        let r = SpotifyReading(notification: ["Player State": "Playing", "Track ID": "", "Name": ""])
        #expect(r?.trackID == nil && r?.title == nil)
    }
    @Test func displayFields() {
        #expect(SpotifyReading(notification: full)?.hasDisplayFields == true)
        #expect(!SpotifyReading(state: .playing, trackID: "x").hasDisplayFields)
    }
    @Test func artworkURLMustBeHTTPS() {
        #expect(SpotifyReading.artworkURL(from: "https://i.scdn.co/image/ab67616d0000b273")
            == URL(string: "https://i.scdn.co/image/ab67616d0000b273"))
        #expect(SpotifyReading.artworkURL(from: "http://example.com/a.jpg") == nil)
        #expect(SpotifyReading.artworkURL(from: "file:///tmp/a.jpg") == nil)
        #expect(SpotifyReading.artworkURL(from: "") == nil)
        #expect(SpotifyReading.artworkURL(from: nil) == nil)
    }
}
```
If Spike 2 required them, also add `httpScdnIsUpgraded` and `trackIDFormsNormalize` (see Task 2 Step 7).

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter SpotifyReadingTests 2>&1 | tail -3`
Expected: build error `cannot find 'SpotifyReading' in scope`.

- [ ] **Step 3: Implement `SpotifyReading.swift`**

- [ ] **Step 4: Run to verify they pass**

Run: `swift test 2>&1 | tail -1`
Expected: starts with `✔ Test run with 75 tests in 9 suites passed` (more if Spike 2 added tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ShimaCore/SpotifyReading.swift Tests/ShimaCoreTests/SpotifyReadingTests.swift
git commit -m "Parse Spotify playback broadcasts into SpotifyReading"
```

---

### Task 8: SpotifyModel reducer and SpotifyChange (PURE, parallel-safe)

**Files:**
- Create: `Sources/ShimaCore/SpotifyModel.swift`
- Test: `Tests/ShimaCoreTests/SpotifyModelTests.swift`

**Interfaces:**
- Consumes: `NowPlaying`, `PlaybackState` (Task 6), `SpotifyReading`, `ReadingSource` (Task 7).
- Produces:
```swift
public enum SpotifyAvailability: Equatable, Sendable { case notRunning, running, permissionDenied }
public enum SpotifyEvent: Equatable, Sendable {
    case launched, terminated, permissionDenied
    case reading(SpotifyReading, source: ReadingSource, at: Date)
}
/// The seam for M2's event bus (forwarded unchanged) and M4's spotify.track_changed trigger.
public enum SpotifyChange: Equatable, Sendable {
    case availabilityChanged(SpotifyAvailability)
    case trackChanged(id: String?)
    case stateChanged(PlaybackState?)
}
public enum NowPlayingContent: Equatable, Sendable {
    case notRunning, permissionDenied, nothingPlaying, track
    public init(availability: SpotifyAvailability, nowPlaying: NowPlaying?)
}
public struct SpotifyModel: Equatable, Sendable {
    public private(set) var availability: SpotifyAvailability   // .notRunning
    public private(set) var nowPlaying: NowPlaying?
    public init()
    public var isLive: Bool { get }          // availability != .notRunning && nowPlaying?.state == .playing
    public var content: NowPlayingContent { get }
    public mutating func apply(_ event: SpotifyEvent) -> (NowPlaying?, [SpotifyChange])
}
```
`NowPlayingContent` precedence: `.notRunning` (availability), then `.permissionDenied`, then `.track` if `nowPlaying != nil`, else `.nothingPlaying`.

**Reducer table** (the spec for `apply`; changes are emitted in the order availability, track, state; anything not listed returns the current `nowPlaying` and `[]`):

| event | condition | result |
|---|---|---|
| `launched` | `.notRunning` | availability `.running`; `[.availabilityChanged(.running)]` |
| `launched` | otherwise | no change |
| `terminated` | any | `nowPlaying = nil`, availability `.notRunning`; `.availabilityChanged(.notRunning)` if it was not `.notRunning`; `.trackChanged(id: nil)` and `.stateChanged(nil)` if there was a track |
| `permissionDenied` | `.running` | availability `.permissionDenied`; `[.availabilityChanged(.permissionDenied)]` |
| `permissionDenied` | otherwise | no change |
| `reading` | `.notRunning` | ignored (a late broadcast after quit) |
| `reading(source: .script)` | `.permissionDenied` | availability `.running` and `.availabilityChanged(.running)`, then the rows below |
| `reading` | `state == .stopped` or `trackID == nil` | `nowPlaying = nil`; `.trackChanged(id: nil)`, `.stateChanged(nil)` if there was a track |
| `reading` | same `trackID` as now | merge: each non-nil field replaces the old one; `artworkURL` kept when the reading has none; if `position != nil`: `position`, `positionDate = at`; else if the state changed: `position = old.position(at: at)`, `positionDate = at`; `.stateChanged(new)` if the state changed |
| `reading` | new `trackID` | new `NowPlaying` (`title/artist/album ?? ""`, `duration ?? 0`, `position ?? 0`, `positionDate = at`, `artworkURL` from the reading); `.trackChanged(id:)`, then `.stateChanged(new)` if it differs from the old state (none counts as different) |

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import ShimaCore

@Suite struct SpotifyModelTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    let art = URL(string: "https://i.scdn.co/image/a")!
    func reading(_ state: PlaybackState, _ id: String? = "spotify:track:a", position: TimeInterval? = 10, art: URL? = nil) -> SpotifyReading {
        SpotifyReading(state: state, trackID: id, title: "Song", artist: "Artist", album: "Album",
                       duration: 200, position: position, artworkURL: art)
    }
    func running() -> SpotifyModel { var m = SpotifyModel(); _ = m.apply(.launched); return m }

    @Test func launchMakesRunning() {
        var m = SpotifyModel()
        let (np, changes) = m.apply(.launched)
        #expect(np == nil && changes == [.availabilityChanged(.running)])
        #expect(m.availability == .running && !m.isLive && m.content == .nothingPlaying)
    }
    @Test func secondLaunchChangesNothing() { var m = running(); #expect(m.apply(.launched).1 == []) }
    @Test func readingWhileNotRunningIsIgnored() {
        var m = SpotifyModel()
        let (np, changes) = m.apply(.reading(reading(.playing), source: .notification, at: t0))
        #expect(np == nil && changes == [] && m.availability == .notRunning && m.content == .notRunning)
    }
    @Test func playingNotificationStartsTrack() {
        var m = running()
        let (np, changes) = m.apply(.reading(reading(.playing), source: .notification, at: t0))
        #expect(np == NowPlaying(trackID: "spotify:track:a", title: "Song", artist: "Artist", album: "Album",
            artworkURL: nil, duration: 200, position: 10, positionDate: t0, state: .playing))
        #expect(changes == [.trackChanged(id: "spotify:track:a"), .stateChanged(.playing)])
        #expect(m.isLive && m.content == .track)
    }
    @Test func sameTrackKeepsArtworkAndUpdatesState() {
        var m = running()
        _ = m.apply(.reading(reading(.playing, art: art), source: .script, at: t0))
        let (np, changes) = m.apply(.reading(reading(.paused, position: 15), source: .notification, at: t0 + 5))
        #expect(np?.artworkURL == art && np?.state == .paused && np?.position == 15 && np?.positionDate == t0 + 5)
        #expect(changes == [.stateChanged(.paused)] && !m.isLive)
    }
    @Test func pauseWithoutPositionFreezesExtrapolatedPosition() {
        var m = running()
        _ = m.apply(.reading(reading(.playing), source: .notification, at: t0))
        let (np, _) = m.apply(.reading(reading(.paused, position: nil), source: .notification, at: t0 + 4))
        #expect(np?.position == 14 && np?.positionDate == t0 + 4)
    }
    @Test func newTrackDropsOldArtwork() {
        var m = running()
        _ = m.apply(.reading(reading(.playing, art: art), source: .script, at: t0))
        let (np, changes) = m.apply(.reading(reading(.playing, "spotify:track:b"), source: .notification, at: t0 + 1))
        #expect(np?.trackID == "spotify:track:b" && np?.artworkURL == nil)
        #expect(changes == [.trackChanged(id: "spotify:track:b")])
    }
    @Test func stoppedClearsNowPlaying() {
        var m = running()
        _ = m.apply(.reading(reading(.playing), source: .notification, at: t0))
        let (np, changes) = m.apply(.reading(SpotifyReading(state: .stopped), source: .notification, at: t0 + 1))
        #expect(np == nil && changes == [.trackChanged(id: nil), .stateChanged(nil)] && !m.isLive)
    }
    @Test func terminatedClearsEverything() {
        var m = running()
        _ = m.apply(.reading(reading(.playing), source: .notification, at: t0))
        let (np, changes) = m.apply(.terminated)
        #expect(np == nil && changes == [.availabilityChanged(.notRunning), .trackChanged(id: nil), .stateChanged(nil)])
        #expect(!m.isLive && m.content == .notRunning)
    }
    @Test func missingTrackIDIsNoTrack() {
        var m = running()
        let (np, changes) = m.apply(.reading(reading(.playing, nil), source: .notification, at: t0))
        #expect(np == nil && changes == [])
    }
    @Test func permissionDeniedUntilAScriptReadingSucceeds() {
        var m = running()
        #expect(m.apply(.permissionDenied).1 == [.availabilityChanged(.permissionDenied)])
        #expect(m.content == .permissionDenied)
        _ = m.apply(.reading(reading(.playing), source: .notification, at: t0))
        #expect(m.availability == .permissionDenied && m.isLive)
        let (_, changes) = m.apply(.reading(reading(.playing), source: .script, at: t0 + 1))
        #expect(changes == [.availabilityChanged(.running)] && m.content == .track)
    }
    @Test func permissionDeniedWhileNotRunningIsIgnored() {
        var m = SpotifyModel()
        #expect(m.apply(.permissionDenied).1 == [] && m.availability == .notRunning)
    }
    @Test func contentKinds() {
        let np = NowPlaying(trackID: "a", title: "", artist: "", album: "", artworkURL: nil,
                            duration: 0, position: 0, positionDate: t0, state: .paused)
        #expect(NowPlayingContent(availability: .notRunning, nowPlaying: np) == .notRunning)
        #expect(NowPlayingContent(availability: .permissionDenied, nowPlaying: np) == .permissionDenied)
        #expect(NowPlayingContent(availability: .running, nowPlaying: nil) == .nothingPlaying)
        #expect(NowPlayingContent(availability: .running, nowPlaying: np) == .track)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter SpotifyModelTests 2>&1 | tail -3`
Expected: build error `cannot find 'SpotifyModel' in scope`.

- [ ] **Step 3: Implement `SpotifyModel.swift` per the table**

- [ ] **Step 4: Run to verify they pass**

Run: `swift test 2>&1 | tail -1`
Expected: starts with `✔ Test run with 88 tests in 10 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShimaCore/SpotifyModel.swift Tests/ShimaCoreTests/SpotifyModelTests.swift
git commit -m "Add SpotifyModel reducer emitting SpotifyChange"
```

---

### Task 9: SpotifyClient, FakeSpotifyClient, SpotifyCoordinator, AppState fields (PURE, parallel-safe; after Spike 1)

**Files:**
- Create: `Sources/ShimaCore/SpotifyClient.swift`, `Sources/ShimaCore/FakeSpotifyClient.swift`, `Sources/ShimaCore/SpotifyCoordinator.swift`
- Modify: `Sources/ShimaCore/AppState.swift`
- Test: `Tests/ShimaCoreTests/SpotifyCoordinatorTests.swift`

**Interfaces:**
- Consumes: Tasks 6-8.
- Produces:
```swift
@MainActor public protocol SpotifyClient: AnyObject {
    var onEvent: (@MainActor (SpotifyEvent) -> Void)? { get set }
    func refresh()                       // one snapshot; result arrives via onEvent (.reading(source: .script) or .permissionDenied)
    func send(_ command: SpotifyCommand)
    func invalidate()                    // Spotify quit: drop anything in flight
}
@MainActor public final class FakeSpotifyClient: SpotifyClient {
    public static let tracks: [(id: String, title: String, duration: TimeInterval)]
        // [("fake:1", "Fake Track One", 200), ("fake:2", "Fake Track Two", 180), ("fake:3", "Fake Track Three", 240)]
    public init(state: PlaybackState, now: @escaping @MainActor () -> Date = { Date() })
    public var onEvent: (@MainActor (SpotifyEvent) -> Void)?
    public private(set) var refreshCount: Int
    public private(set) var sent: [SpotifyCommand]
    public func refresh()                 // .reading(current, source: .script, at: now())
    public func send(_ command: SpotifyCommand)  // mutate like Spotify, then .reading(current, source: .notification, at: now())
    public func setState(_ state: PlaybackState) // fake control: mutate, then a .notification reading
    public func invalidate()              // no-op
}
public enum FakeSpotifyMode {
    /// SHIMA_FAKE_SPOTIFY: nil or "" → nil (real Spotify); "playing" → .playing; any other value → .paused (never silently real).
    public static func initialState(_ value: String?) -> PlaybackState?
}
@MainActor public final class SpotifyCoordinator {
    public init(client: any SpotifyClient, state: AppState)   // does NOT set client.onEvent; the owner wires it
    public private(set) var model: SpotifyModel
    public var onLiveChange: (@MainActor (Bool) -> Void)?
    public var onChanges: (@MainActor ([SpotifyChange]) -> Void)?
    public var onArtwork: (@MainActor (_ trackID: String?, _ url: URL?) -> Void)?
    public func handle(_ event: SpotifyEvent)
    public func islandOpened()
    public func perform(_ command: SpotifyCommand)
}
// AppState gains:
public var live: Bool = false                                // wings applied (changed only while the panel is small, Task 14)
public var nowPlaying: NowPlaying? = nil
public var spotifyAvailability: SpotifyAvailability = .notRunning
public var content: NowPlayingContent { get }               // NowPlayingContent(availability:nowPlaying:)
```
Fake readings carry `title`, `artist: "shima fake"`, `album: "Fixture"`, `duration`, `position` (extrapolated from its own clock), `artworkURL: nil` (fake mode never touches the network). `next`/`previous` move through `tracks` with wrap-around and position 0; `playPause` toggles playing/paused.

`handle(_:)`, in this order:
1. Remember `wasLive = model.isLive` and `oldArt = (model.nowPlaying?.trackID, model.nowPlaying?.artworkURL)`.
2. `let (np, changes) = model.apply(event)`; write `state.nowPlaying = np`, `state.spotifyAvailability = model.availability`.
3. `if !changes.isEmpty { onChanges?(changes) }`; `if model.isLive != wasLive { onLiveChange?(model.isLive) }`; if `(np?.trackID, np?.artworkURL) != oldArt`, `onArtwork?(np?.trackID, np?.artworkURL)`.
4. On `.terminated`: `client.invalidate()`, `artworkAskedFor = nil`.
5. **Refresh policy, last** (the fake answers synchronously, so a refresh re-enters `handle`): only for `.reading(r, source: .notification, _)` while `model.availability != .notRunning`, call `client.refresh()` when `model.availability == .permissionDenied`, or `!r.hasDisplayFields`, or (`np != nil && np!.artworkURL == nil && artworkAskedFor != np!.trackID`, then set `artworkAskedFor = np!.trackID`). Never on `.launched`, never for script readings.

`islandOpened()`: `client.refresh()` only when `model.availability != .notRunning` (re-syncs the position, and retries after a denial).
`perform(_:)`: `client.send(command)` only when `model.availability == .running`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import ShimaCore

@MainActor final class TestClient: SpotifyClient {
    var onEvent: (@MainActor (SpotifyEvent) -> Void)?
    var refreshes = 0, invalidations = 0
    var sent: [SpotifyCommand] = []
    func refresh() { refreshes += 1 }
    func send(_ command: SpotifyCommand) { sent.append(command) }
    func invalidate() { invalidations += 1 }
}

struct ArtworkTap: Equatable { let id: String?; let url: URL? }

@MainActor final class Taps {
    var lives: [Bool] = []
    var changes: [[SpotifyChange]] = []
    var artworks: [ArtworkTap] = []
}

@Suite @MainActor struct SpotifyCoordinatorTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    let art = URL(string: "https://i.scdn.co/image/a")!

    func make() -> (SpotifyCoordinator, TestClient, AppState, Taps) {
        let client = TestClient(), state = AppState(), taps = Taps()
        let c = SpotifyCoordinator(client: client, state: state)
        c.onLiveChange = { taps.lives.append($0) }
        c.onChanges = { taps.changes.append($0) }
        c.onArtwork = { taps.artworks.append(ArtworkTap(id: $0, url: $1)) }
        return (c, client, state, taps)
    }
    func note(_ s: PlaybackState = .playing, _ id: String = "a") -> SpotifyEvent {
        .reading(SpotifyReading(state: s, trackID: id, title: "T", artist: "A", album: "L", duration: 200, position: 1),
                 source: .notification, at: t0)
    }
    func script(_ id: String = "a", art: URL?) -> SpotifyEvent {
        .reading(SpotifyReading(state: .playing, trackID: id, title: "T", artist: "A", album: "L", duration: 200,
                                position: 1, artworkURL: art), source: .script, at: t0)
    }

    @Test func launchSendsNoAppleEvents() {
        let (c, client, state, _) = make()
        c.handle(.launched)
        #expect(client.refreshes == 0 && client.sent == [] && state.spotifyAvailability == .running)
    }
    @Test func playingNotificationGoesLiveOnce() {
        let (c, _, state, taps) = make()
        c.handle(.launched); c.handle(note()); c.handle(note())
        #expect(taps.lives == [true] && state.nowPlaying?.trackID == "a" && state.content == .track)
    }
    @Test func pauseEndsLive() {
        let (c, _, _, taps) = make()
        c.handle(.launched); c.handle(note()); c.handle(note(.paused))
        #expect(taps.lives == [true, false])
    }
    @Test func terminateClearsStateAndInvalidatesClient() {
        let (c, client, state, taps) = make()
        c.handle(.launched); c.handle(note()); c.handle(.terminated)
        #expect(taps.lives == [true, false] && state.nowPlaying == nil)
        #expect(state.spotifyAvailability == .notRunning && client.invalidations == 1)
    }
    @Test func readingAfterTerminateIsIgnored() {
        let (c, client, state, taps) = make()
        c.handle(.launched); c.handle(.terminated); c.handle(note())
        #expect(state.nowPlaying == nil && taps.lives == [] && client.refreshes == 0)
    }
    @Test func missingArtworkRefreshesOncePerTrack() {
        let (c, client, _, _) = make()
        c.handle(.launched); c.handle(note(.playing, "a")); c.handle(note(.playing, "a")); c.handle(note(.playing, "b"))
        #expect(client.refreshes == 2)
    }
    @Test func knownArtworkDoesNotRefresh() {
        let (c, client, _, _) = make()
        c.handle(.launched); c.handle(note()); c.handle(script(art: art)); c.handle(note())
        #expect(client.refreshes == 1)
    }
    @Test func incompleteNotificationRefreshesEachTime() {
        let (c, client, _, _) = make()
        let bare = SpotifyEvent.reading(SpotifyReading(state: .playing, trackID: "a"), source: .notification, at: t0)
        c.handle(.launched); c.handle(bare); c.handle(bare)
        #expect(client.refreshes == 2)
    }
    @Test func scriptReadingNeverTriggersRefresh() {
        let (c, client, _, _) = make()
        c.handle(.launched); c.handle(script(art: nil))
        #expect(client.refreshes == 0)
    }
    @Test func islandOpenRefreshesOnlyWhenRunning() {
        let (c, client, _, _) = make()
        c.islandOpened()
        #expect(client.refreshes == 0)
        c.handle(.launched); c.islandOpened()
        #expect(client.refreshes == 1)
    }
    @Test func commandsOnlyWhenRunning() {
        let (c, client, _, _) = make()
        c.perform(.next)
        #expect(client.sent == [])
        c.handle(.launched); c.perform(.next)
        #expect(client.sent == [.next])
    }
    @Test func permissionDeniedRetriesOnlyOnNotificationOrOpen() {
        let (c, client, state, _) = make()
        c.handle(.launched); c.handle(.permissionDenied); c.perform(.playPause)
        #expect(client.sent == [] && client.refreshes == 0 && state.content == .permissionDenied)
        c.handle(note()); c.handle(note())
        #expect(client.refreshes == 2)
        c.islandOpened()
        #expect(client.refreshes == 3)
    }
    @Test func changesAreForwardedForTheBus() {
        let (c, _, _, taps) = make()
        c.handle(.launched); c.handle(note())
        #expect(taps.changes == [[.availabilityChanged(.running)], [.trackChanged(id: "a"), .stateChanged(.playing)]])
    }
    @Test func artworkCallbackFollowsTrackAndURL() {
        let (c, _, _, taps) = make()
        c.handle(.launched); c.handle(note(.playing, "a")); c.handle(script("a", art: art)); c.handle(note(.playing, "a")); c.handle(note(.playing, "b"))
        #expect(taps.artworks == [ArtworkTap(id: "a", url: nil), ArtworkTap(id: "a", url: art), ArtworkTap(id: "b", url: nil)])
    }
    @Test func fakeModeValues() {
        #expect(FakeSpotifyMode.initialState(nil) == nil)
        #expect(FakeSpotifyMode.initialState("") == nil)
        #expect(FakeSpotifyMode.initialState("playing") == .playing)
        #expect(FakeSpotifyMode.initialState("paused") == .paused)
        #expect(FakeSpotifyMode.initialState("1") == .paused)
    }
    @Test func appStateSpotifyDefaults() {
        let s = AppState()
        #expect(!s.live && s.nowPlaying == nil && s.spotifyAvailability == .notRunning && s.content == .notRunning)
    }
}

@MainActor final class EventBox { var events: [SpotifyEvent] = [] }

@Suite @MainActor struct FakeSpotifyClientTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    func reading(_ e: SpotifyEvent?) -> (SpotifyReading, ReadingSource)? {
        if case .reading(let r, let s, _)? = e { return (r, s) } else { return nil }
    }
    @Test func refreshReportsTheFixture() {
        let fake = FakeSpotifyClient(state: .playing, now: { self.t0 }), box = EventBox()
        fake.onEvent = { box.events.append($0) }
        fake.refresh()
        let r = reading(box.events.last)
        #expect(fake.refreshCount == 1 && r?.1 == .script)
        #expect(r?.0.trackID == "fake:1" && r?.0.state == .playing && r?.0.artworkURL == nil && r?.0.hasDisplayFields == true)
    }
    @Test func commandsActLikeSpotify() {
        let fake = FakeSpotifyClient(state: .playing, now: { self.t0 }), box = EventBox()
        fake.onEvent = { box.events.append($0) }
        fake.send(.next)
        #expect(reading(box.events.last)?.0.trackID == "fake:2" && reading(box.events.last)?.1 == .notification)
        fake.send(.playPause)
        #expect(reading(box.events.last)?.0.state == .paused)
        fake.send(.previous)
        #expect(reading(box.events.last)?.0.trackID == "fake:1")
        #expect(fake.sent == [.next, .playPause, .previous])
    }
}
```
If Spike 1 required it (rate above 6 per minute), add `positionOnlyUpdateWhileCollapsedIsSkipped` and the rule from Task 1 Step 5.

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter "SpotifyCoordinatorTests|FakeSpotifyClientTests" 2>&1 | tail -3`
Expected: build error `cannot find type 'SpotifyClient' in scope`.

- [ ] **Step 3: Implement the three files and the `AppState` fields** (`AppState` imports `Observation` and `Foundation`).

- [ ] **Step 4: Run to verify they pass**

Run: `swift test 2>&1 | tail -1 && swift build 2>&1 | tail -1`
Expected: starts with `✔ Test run with 106 tests in 12 suites passed`; `Build complete!`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShimaCore/SpotifyClient.swift Sources/ShimaCore/FakeSpotifyClient.swift Sources/ShimaCore/SpotifyCoordinator.swift Sources/ShimaCore/AppState.swift Tests/ShimaCoreTests/SpotifyCoordinatorTests.swift
git commit -m "Add SpotifyClient, fake client and coordinator with refresh policy"
```

---

### Task 10: SpotifyRequestGate and Apple Event error mapping (PURE, parallel-safe)

8.4: "one in flight plus a dirty flag, tagged with a sequence number and pid; stale results are dropped on the main actor; -600 and -609 mean not running; -1712 is a timeout."

**Files:**
- Create: `Sources/ShimaCore/SpotifyRequestGate.swift`
- Test: `Tests/ShimaCoreTests/SpotifyRequestGateTests.swift`

**Interfaces:**
- Produces:
```swift
public struct SpotifyRequestGate: Equatable, Sendable {
    public struct Ticket: Equatable, Sendable { public let seq: Int; public let pid: Int32; public init(seq:pid:) }
    public struct Outcome: Equatable, Sendable { public let apply: Bool; public let next: Ticket?; public init(apply:next:) }
    public init()
    public var inFlight: Bool { get }
    /// A ticket to start a snapshot now, or nil when one is already in flight (then a follow-up is owed).
    public mutating func request(pid: Int32) -> Ticket?
    /// A ticket for a command: never coalesced, never in flight.
    public mutating func ticket(pid: Int32) -> Ticket
    /// Main actor, when a request or command finishes. apply = not invalidated and pid still current.
    /// next = the owed follow-up snapshot (only when the finished ticket was the in-flight one and currentPid != nil).
    public mutating func finish(_ ticket: Ticket, currentPid: Int32?) -> Outcome
    /// Spotify quit: every ticket issued so far is stale; no follow-up is owed.
    public mutating func invalidate()
}
public enum SpotifyScriptError: Error, Equatable, Sendable {
    case notRunning(code: Int)   // -600 procNotFound, -609 connectionInvalid
    case permissionDenied        // -1743 errAEEventNotPermitted
    case timeout                 // -1712 errAETimeout
    case other(code: Int)
    public init(code: Int)
}
```
State: `nextSeq` (starts 1), `current: Ticket?`, `dirty`, `staleThrough` (0). `finish` applies when `ticket.seq > staleThrough && ticket.pid == currentPid`. `invalidate()` sets `staleThrough = nextSeq - 1` and `dirty = false`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import ShimaCore

@Suite struct SpotifyRequestGateTests {
    typealias T = SpotifyRequestGate.Ticket
    typealias O = SpotifyRequestGate.Outcome

    @Test func firstRequestStarts() {
        var g = SpotifyRequestGate()
        #expect(g.request(pid: 7) == T(seq: 1, pid: 7) && g.inFlight)
    }
    @Test func finishWithoutDirtyHasNoFollowUp() {
        var g = SpotifyRequestGate(); let t = g.request(pid: 7)!
        #expect(g.finish(t, currentPid: 7) == O(apply: true, next: nil) && !g.inFlight)
    }
    @Test func requestsWhileInFlightCoalesceIntoOneFollowUp() {
        var g = SpotifyRequestGate(); let t1 = g.request(pid: 7)!
        for _ in 0..<5 { #expect(g.request(pid: 7) == nil) }
        let o = g.finish(t1, currentPid: 7)
        #expect(o == O(apply: true, next: T(seq: 2, pid: 7)))
        #expect(g.finish(o.next!, currentPid: 7) == O(apply: true, next: nil))
    }
    @Test func resultFromOldPidIsDropped() {
        var g = SpotifyRequestGate(); let t = g.request(pid: 7)!
        #expect(g.finish(t, currentPid: 9) == O(apply: false, next: nil))
    }
    @Test func resultAfterInvalidateIsDropped() {
        var g = SpotifyRequestGate(); let t = g.request(pid: 7)!
        g.invalidate()
        #expect(g.finish(t, currentPid: 7).apply == false)
    }
    @Test func invalidateClearsTheOwedFollowUp() {
        var g = SpotifyRequestGate(); let t = g.request(pid: 7)!
        _ = g.request(pid: 7); g.invalidate()
        #expect(g.finish(t, currentPid: 7) == O(apply: false, next: nil))
    }
    @Test func notRunningAtFinishGivesNoFollowUp() {
        var g = SpotifyRequestGate(); let t = g.request(pid: 7)!
        _ = g.request(pid: 7)
        #expect(g.finish(t, currentPid: nil) == O(apply: false, next: nil))
    }
    @Test func commandTicketsAreNeverCoalesced() {
        var g = SpotifyRequestGate(); _ = g.request(pid: 7)
        let c1 = g.ticket(pid: 7), c2 = g.ticket(pid: 7)
        #expect(c1 == T(seq: 2, pid: 7) && c2 == T(seq: 3, pid: 7))
        #expect(g.finish(c1, currentPid: 7) == O(apply: true, next: nil) && g.inFlight)
    }
    @Test func scriptErrorCodes() {
        #expect(SpotifyScriptError(code: -600) == .notRunning(code: -600))
        #expect(SpotifyScriptError(code: -609) == .notRunning(code: -609))
        #expect(SpotifyScriptError(code: -1743) == .permissionDenied)
        #expect(SpotifyScriptError(code: -1712) == .timeout)
        #expect(SpotifyScriptError(code: -10000) == .other(code: -10000))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter SpotifyRequestGateTests 2>&1 | tail -3`
Expected: build error `cannot find 'SpotifyRequestGate' in scope`.

- [ ] **Step 3: Implement `SpotifyRequestGate.swift`**

- [ ] **Step 4: Run to verify they pass**

Run: `swift test 2>&1 | tail -1`
Expected: starts with `✔ Test run with 115 tests in 13 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShimaCore/SpotifyRequestGate.swift Tests/ShimaCoreTests/SpotifyRequestGateTests.swift
git commit -m "Add Spotify request gate (coalescing, sequence and pid tags) and error mapping"
```

---

### Task 11: Live island geometry and open-island layout (PURE, parallel-safe; after Task 6)

8.2 and 8.4: the idle frame and the idle hot rect become functions of `(notch, live)`; the open-island arithmetic is fixed in one place so views and scripts agree.

**Files:**
- Modify: `Sources/ShimaCore/IslandLayout.swift`, `Tests/ShimaCoreTests/IslandLayoutTests.swift`
- Modify (call sites only, `live: false`): `Sources/Shima/IslandPanelController.swift`, `Sources/Shima/IslandView.swift`
- Create: `Sources/ShimaCore/NowPlayingLayout.swift`, `Tests/ShimaCoreTests/NowPlayingLayoutTests.swift`

**Interfaces:**
- Consumes: `SpotifyCommand` (Task 6).
- Produces (the old signatures without `live:` are **replaced**, not overloaded, so no call site can forget the flag):
```swift
// IslandLayout
public static let liveWingWidth: CGFloat = 33
public static func collapsedMetrics(notch: CGRect, live: Bool) -> IslandShapeMetrics   // width notch.width + (live ? 66 : 0), height notch.height, radius 9, ear 0
public static func metrics(for mode: IslandMode, notch: CGRect, live: Bool) -> IslandShapeMetrics
public static func idleFrame(notch: CGRect, live: Bool) -> CGRect                      // live ? notch.insetBy(dx: -33, dy: 0) : notch
public static func panelFrame(notch: CGRect, live: Bool, expanded: Bool) -> CGRect      // expanded frame ignores live
public static func hotRect(_ region: HotRegion, notch: CGRect, live: Bool, panelFrame: CGRect) -> CGRect // .idle = idleFrame in panel-local coords

// NowPlayingLayout: island-local, y-down, inside IslandLayout.expanded (360 x 165); the notch strip is y 0..32
public enum NowPlayingLayout {
    public static let artwork = CGRect(x: 14, y: 44, width: 88, height: 88)
    public static let artworkRadius: CGFloat = 10
    public static let column = CGRect(x: 116, y: 44, width: 230, height: 100)  // x 116..346, y 44..144
    public static let titleTop: CGFloat = 44, artistTop: CGFloat = 64, progressTop: CGFloat = 88, timesTop: CGFloat = 96
    public static let titleSize: CGFloat = 15, artistSize: CGFloat = 12.5, timesSize: CGFloat = 11, progressHeight: CGFloat = 4
    public static func controlRect(_ command: SpotifyCommand) -> CGRect
        // previous (173, 114, 28, 28), playPause (215, 112, 32, 32), next (261, 114, 28, 28)
    /// Centre of a control in global top-left CG points, for scripts. topY is the CG y of the screen's top edge.
    public static func controlCenter(_ command: SpotifyCommand, notchMidX: CGFloat, topY: CGFloat) -> CGPoint
    public static let miniArtwork = CGSize(width: 20, height: 20), miniArtworkRadius: CGFloat = 5
    public static let equalizer = CGSize(width: 16, height: 14)
    public static let barWidth: CGFloat = 2.5, barGap: CGFloat = 2, barCount = 4
}
```
The controls row (y 112..144) sits below the artwork's bottom (132), inside the island (165) and clear of the 24 pt bottom corners.

- [ ] **Step 1: Write the failing tests**

In `IslandLayoutTests`, update every existing call to the new signatures with `live: false` (behavior unchanged), then add:
```swift
    let live = CGRect(x: 613, y: 924, width: 245, height: 32)

    @Test func liveWingsAre33() { #expect(IslandLayout.liveWingWidth == 33) }
    @Test func liveIdleFrameOnThisMac() {
        #expect(IslandLayout.idleFrame(notch: notch, live: true) == live)
        #expect(IslandLayout.panelFrame(notch: notch, live: true, expanded: false) == live)
    }
    @Test func liveFrameClearsFirstStatusItem() { #expect(IslandLayout.idleFrame(notch: notch, live: true).maxX == 858) } // item at 860
    @Test func notLiveIdleFrameIsTheNotch() { #expect(IslandLayout.idleFrame(notch: notch, live: false) == notch) }
    @Test func expandedPanelIgnoresLive() { #expect(IslandLayout.panelFrame(notch: notch, live: true, expanded: true) == big) }
    @Test func liveCollapsedMetrics() {
        #expect(IslandLayout.collapsedMetrics(notch: notch, live: true) == IslandShapeMetrics(width: 245, height: 32, bottomRadius: 9, earRadius: 0))
        #expect(IslandLayout.metrics(for: .expanded, notch: notch, live: true) == IslandLayout.expanded)
    }
    @Test func liveIdleHotRectInIdlePanel() {
        #expect(IslandLayout.hotRect(.idle, notch: notch, live: true, panelFrame: live) == CGRect(x: 0, y: 0, width: 245, height: 32))
    }
    @Test func liveIdleHotRectInsideBigPanel() {
        #expect(IslandLayout.hotRect(.idle, notch: notch, live: true, panelFrame: big) == CGRect(x: 75.5, y: 141, width: 245, height: 32))
    }
    @Test func liveOnVirtualHotZone() {
        let n = CGRect(x: 620, y: 868, width: 200, height: 32)
        #expect(IslandLayout.idleFrame(notch: n, live: true) == CGRect(x: 587, y: 868, width: 266, height: 32))
    }
```
`Tests/ShimaCoreTests/NowPlayingLayoutTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import ShimaCore

@Suite struct NowPlayingLayoutTests {
    let island = CGRect(x: 0, y: 0, width: 360, height: 165)
    var rects: [CGRect] { [NowPlayingLayout.artwork, NowPlayingLayout.column] + SpotifyCommand.allCases.map(NowPlayingLayout.controlRect) }

    @Test func artworkAndColumnMatchSpec() {
        #expect(NowPlayingLayout.artwork == CGRect(x: 14, y: 44, width: 88, height: 88))
        #expect(NowPlayingLayout.column.minX == 116 && NowPlayingLayout.column.maxX == 346)
    }
    @Test func contentSitsBelowTheNotchStripInsideTheIsland() {
        for r in rects { #expect(r.minY >= 32 && island.contains(r)) }
    }
    @Test func controlsAreSizedAndSpaced() {
        let p = NowPlayingLayout.controlRect(.previous), m = NowPlayingLayout.controlRect(.playPause), n = NowPlayingLayout.controlRect(.next)
        #expect(p.size == CGSize(width: 28, height: 28) && n.size == p.size && m.size == CGSize(width: 32, height: 32))
        #expect(m.minX - p.maxX == 14 && n.minX - m.maxX == 14 && p.midY == m.midY && n.midY == m.midY)
        #expect(NowPlayingLayout.column.contains(p) && NowPlayingLayout.column.contains(n))
    }
    @Test func controlCentersOnThisMac() {
        #expect(NowPlayingLayout.controlCenter(.previous, notchMidX: 735.5, topY: 0) == CGPoint(x: 742.5, y: 128))
        #expect(NowPlayingLayout.controlCenter(.playPause, notchMidX: 735.5, topY: 0) == CGPoint(x: 786.5, y: 128))
        #expect(NowPlayingLayout.controlCenter(.next, notchMidX: 735.5, topY: 0) == CGPoint(x: 830.5, y: 128))
    }
    @Test func wingContentFits() {
        let bars = CGFloat(NowPlayingLayout.barCount) * NowPlayingLayout.barWidth + CGFloat(NowPlayingLayout.barCount - 1) * NowPlayingLayout.barGap
        #expect(bars == NowPlayingLayout.equalizer.width && bars <= IslandLayout.liveWingWidth)
        #expect(NowPlayingLayout.miniArtwork.width <= IslandLayout.liveWingWidth && NowPlayingLayout.miniArtwork.height <= 32)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter "IslandLayoutTests|NowPlayingLayoutTests" 2>&1 | tail -3`
Expected: build errors (`extra argument 'live' in call` / `cannot find 'NowPlayingLayout' in scope`).

- [ ] **Step 3: Implement; update the Shima call sites**

In `IslandPanelController.setPanelFrame` and `refreshHotRect`, and in `IslandView`'s `metrics(for:notch:)` call, pass `live: false`. Task 14 replaces these with the real flag.

- [ ] **Step 4: Run to verify they pass**

Run: `swift test 2>&1 | tail -1 && swift build 2>&1 | tail -1`
Expected: starts with `✔ Test run with 129 tests in 14 suites passed`; `Build complete!`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShimaCore/IslandLayout.swift Sources/ShimaCore/NowPlayingLayout.swift Tests/ShimaCoreTests/IslandLayoutTests.swift Tests/ShimaCoreTests/NowPlayingLayoutTests.swift Sources/Shima/IslandPanelController.swift Sources/Shima/IslandView.swift
git commit -m "Make the idle frame and hot rect functions of (notch, live); add open-island layout"
```

---

### Task 12: HoverMachine `.idleGeometryChanged` (PURE, parallel-safe; after Spike 3)

8.4: one new input. It re-applies the idle frame only while the panel is small; while it is large (expanded, leaving, collapsing, or dwelling after a re-entry during a collapse) it does nothing, and the next `shrinkPanel` picks up the new idle frame.

**Files:**
- Modify: `Sources/ShimaCore/HoverMachine.swift`, `Sources/ShimaCore/HoverController.swift`
- Test: `Tests/ShimaCoreTests/HoverMachineTests.swift`, `Tests/ShimaCoreTests/HoverControllerTests.swift`

**Interfaces:**
- Produces: `HoverInput.idleGeometryChanged`; `HoverController.idleGeometryChanged()` (public, `handle(.idleGeometryChanged)`).
- Transition (added to the M0 table, placed right after `reset` and before `default`): **any phase | `idleGeometryChanged` | phase unchanged | `[.shrinkPanel]` if `!panelLarge`, else `[]`**. It touches neither `pointerInside`, `generation` nor timers. (If Spike 3 changed the rule, use the recorded rule and its extra tests.)

- [ ] **Step 1: Write the failing tests**

In `HoverMachineTests` (uses the existing `run(_:)` helper; `i`/`o` below are `.pointer(inside: true/false)`):
```swift
    @Test func geometryChangeWhenCollapsedReappliesIdleFrame() {
        let (m, e) = run([.idleGeometryChanged])
        #expect(m.phase == .collapsed && e == [.shrinkPanel])
    }
    @Test func geometryChangeWhileDwellingSmallReappliesIdleFrame() {
        let (m, e) = run([.pointer(inside: true), .idleGeometryChanged])
        #expect(m.phase == .dwelling && e == [.shrinkPanel])
    }
    @Test func geometryChangeWhileDwellingKeepsTheDwell() {
        let (m, e) = run([.pointer(inside: true), .idleGeometryChanged, .dwellElapsed])
        #expect(m.phase == .expanded && e == [.growPanel, .setHotRegion(.expanded), .animateExpand])
    }
    @Test func geometryChangeWhileExpandedWaits() {
        let (m, e) = run([.pointer(inside: true), .dwellElapsed, .idleGeometryChanged])
        #expect(m.phase == .expanded && e == [])
    }
    @Test func geometryChangeWhileLeavingWaits() {
        let (m, e) = run([.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .idleGeometryChanged])
        #expect(m.phase == .leaving && e == [])
    }
    @Test func geometryChangeWhileCollapsingWaits() {
        let inputs: [HoverInput] = [.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .leaveElapsed, .idleGeometryChanged]
        let (m, e) = run(inputs)
        #expect(m.phase == .collapsing && e == [])
        let (done, finish) = run(inputs + [.collapseFinished(generation: 1)])
        #expect(done.phase == .collapsed && finish == [.shrinkPanel])
    }
    @Test func geometryChangeWhileDwellingLargeWaitsForCollapseFinish() {
        let inputs: [HoverInput] = [.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .leaveElapsed, .pointer(inside: true), .idleGeometryChanged]
        let (m, e) = run(inputs)
        #expect(m.phase == .dwelling && e == [])
        let (_, finish) = run(inputs + [.collapseFinished(generation: 1)])
        #expect(finish == [.shrinkPanel])
        let (grown, grow) = run(inputs + [.collapseFinished(generation: 1), .dwellElapsed])
        #expect(grown.phase == .expanded && grow == [.growPanel, .setHotRegion(.expanded), .animateExpand])
    }
    @Test func staleCollapseFinishAfterGeometryChangeIgnored() {
        let (m, e) = run([.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .leaveElapsed, .pointer(inside: true),
                          .dwellElapsed, .idleGeometryChanged, .collapseFinished(generation: 1)])
        #expect(m.phase == .expanded && e == [])
    }
    @Test func geometryChangeKeepsPointerDedupe() {
        let (m, e) = run([.pointer(inside: true), .idleGeometryChanged, .pointer(inside: true)])
        #expect(m.phase == .dwelling && e == [])
    }
```
In `HoverControllerTests`:
```swift
    @Test func idleGeometryChangeIsForwardedWhenSmall() {
        let (controller, recorder) = make()
        controller.idleGeometryChanged()
        #expect(recorder.effects == [.shrinkPanel] && clock.pendingCount == 0)
    }
    @Test func liveToggleWhileDwellingKeepsOneTimer() {
        let (controller, recorder) = make()
        controller.pointer(inside: true)
        clock.advance(by: .milliseconds(40))
        controller.idleGeometryChanged()
        #expect(clock.pendingCount == 1)
        clock.advance(by: .milliseconds(40))
        #expect(controller.phase == .expanded && recorder.count(.growPanel) == 1)
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter "HoverMachineTests|HoverControllerTests" 2>&1 | tail -3`
Expected: build error `type 'HoverInput' has no member 'idleGeometryChanged'`.

- [ ] **Step 3: Implement the case and `idleGeometryChanged()`**

- [ ] **Step 4: Run to verify they pass**

Run: `swift test 2>&1 | tail -1 && swift build 2>&1 | tail -1`
Expected: starts with `✔ Test run with 140 tests in 14 suites passed`; `Build complete!`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShimaCore/HoverMachine.swift Sources/ShimaCore/HoverController.swift Tests/ShimaCoreTests/HoverMachineTests.swift Tests/ShimaCoreTests/HoverControllerTests.swift
git commit -m "Add idleGeometryChanged to the hover machine: re-apply the idle frame only while small"
```

---

### Task 13: SpotifyService with fake mode, logging and wiring (GLUE, sequential)

Fake mode first, so every later glue task can be verified without Spotify.

**Files:**
- Modify: `Sources/Shima/Log.swift`, `Sources/Shima/AppDelegate.swift`, `Sources/Shima/IslandPanelController.swift` (expose `state` and `media`, add `setLive` stub)
- Create: `Sources/Shima/IslandMedia.swift`, `Sources/Shima/SpotifyService.swift`

**Interfaces:**
- Consumes: `SpotifyCoordinator`, `FakeSpotifyClient`, `FakeSpotifyMode`, `SpotifyEvent`, `SpotifyCommand` (Task 9).
- Produces:
  - `Log.spotify`, `Log.artwork`, `Log.eq`, `Log.focus` (subsystem `local.shima`, categories `spotify`, `artwork`, `eq`, `focus`). `EqualizerView.swift` switches to `Log.eq`.
  - `@Observable @MainActor final class IslandMedia { var artwork: NSImage? = nil; var equalizerFrozen = false }`
  - `@MainActor final class SpotifyService: NSObject`:
    - `init(state: AppState, media: IslandMedia, environment: [String: String] = ProcessInfo.processInfo.environment)`
    - `var onLiveChange: (@MainActor (Bool) -> Void)?`, `func start()`, `func islandOpened()`, `func perform(_ command: SpotifyCommand)`
    - `func receive(_ event: SpotifyEvent)`: the single funnel: logs, then `coordinator.handle(event)`. The client's `onEvent` is wired to it.
  - `IslandPanelController`: `let state: AppState`, `let media = IslandMedia()`, `func setLive(_ live: Bool)` (this task: logs `live desired=<bool>` only), `var onIslandOpened: (@MainActor () -> Void)?` (called from `.animateExpand`).
- Fixed log formats (scripts grep them):
  - `spotify mode fake state=playing|paused` / `spotify mode real running=true|false` (real: Task 17; this task logs `spotify mode real running=false (not wired)` and does nothing else)
  - `spotify event launched|terminated|permissionDenied` / `spotify event reading src=notification|script state=<state> track=<id or none>` (never title or artist)
  - `spotify changes <String(describing: changes)>`, `spotify live true|false`
  - `fake <cmd>` for every fake control command received, including `fake ping`
  - `app became active` (error level, `Log.focus`)

- [ ] **Step 1: `Log.swift`, `IslandMedia.swift`**

- [ ] **Step 2: `SpotifyService` fake path**

`start()` reads `FakeSpotifyMode.initialState(environment["SHIMA_FAKE_SPOTIFY"])`. With a state: create `FakeSpotifyClient(state:)`, `client.onEvent = { [weak self] in self?.receive($0) }`, coordinator callbacks (`onLiveChange` logs `spotify live …` and forwards to `self.onLiveChange`; `onChanges` logs), log `spotify mode fake state=…`, register the fake control observer, then `receive(.launched)` and `client.refresh()` (mirrors the real start-up snapshot).
Fake control: `DistributedNotificationCenter.default().addObserver(self, selector: #selector(fakeControl(_:)), name: .init("local.shima.fake-spotify"), object: nil, suspensionBehavior: .deliverImmediately)` (the app is never active, so the default suspension would hold notifications forever). `@objc nonisolated func fakeControl(_ note: Notification)` reads `note.object as? String` into a `let` and calls `MainActor.assumeIsolated { self.handleFake(cmd) }`. Commands: `ping` (log only), `playing`/`paused` → `fake.setState`, `next`/`previous` → `fake.send`, `quit` → `receive(.terminated)`, `launch` → `receive(.launched)`, `eq-frozen`/`eq-animating` → `media.equalizerFrozen = true/false`. Every command logs `fake <cmd>` first; unknown ones log `fake unknown <cmd>`.
`islandOpened()` → `coordinator.islandOpened()`; `perform` → `coordinator.perform`.

- [ ] **Step 3: Wire `AppDelegate`**

Keep `islandController`; add `private lazy var spotify = SpotifyService(state: islandController.state, media: islandController.media)`. In `applicationDidFinishLaunching`, after `showPanel()`: `spotify.onLiveChange = { [weak self] in self?.islandController.setLive($0) }`, `islandController.onIslandOpened = { [weak self] in self?.spotify.islandOpened() }`, `spotify.start()`. Observe `NSApplication.didBecomeActiveNotification` and log `app became active` (error).

- [ ] **Step 4: Build and verify by running (AUTOMATED)**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -1`. Expected: `Build complete!`, 140 tests pass.
Run: `SHIMA_FAKE_SPOTIFY=playing scripts/run.sh && sleep 2 && scripts/with-log.sh .build/t13.log -- swift scripts/drive.swift "fake ping; sleep 100; fake paused; sleep 100; fake playing; sleep 100; fake next; sleep 100; fake quit; sleep 100; fake playing; sleep 100; fake launch; sleep 100; fake playing; sleep 100" && grep -E "fake |spotify (event|live)" .build/t13.log | sed -E 's/^.*\] //'`
Expected, in order: `fake ping`; `fake paused`, `spotify event reading src=notification state=paused track=fake:1`, `spotify live false`; `fake playing`, `… state=playing …`, `spotify live true`; `fake next`, `… track=fake:2`; `fake quit`, `spotify event terminated`, `spotify live false`; `fake playing`, `spotify event reading …` with **no** `spotify live` (ignored while not running); `fake launch`, `spotify event launched`; `fake playing`, `spotify event reading …`, `spotify live true`.
Also: `/usr/bin/log show --last 1m --predicate 'subsystem == "local.shima"' | grep -E "spotify mode|became active"` shows `spotify mode fake state=playing` and no `app became active`.
Without the variable: `scripts/run.sh` logs `spotify mode real running=false (not wired)` and nothing else from `spotify`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shima/Log.swift Sources/Shima/IslandMedia.swift Sources/Shima/SpotifyService.swift Sources/Shima/AppDelegate.swift Sources/Shima/IslandPanelController.swift Sources/Shima/EqualizerView.swift
git commit -m "Add SpotifyService with fake mode, control channel and Spotify logging"
```

---

### Task 14: Live geometry in the panel (GLUE, sequential)

The glue for 8.4's live rule: a desired live flag from Spotify, an applied flag (`state.live`) that changes only on `shrinkPanel` (i.e. only while the panel is small), the live frame and hot rect, and the widened collapsed shape. Wings content comes in Task 19; here the wings are plain black (red with `SHIMA_DEBUG`).

**Files:**
- Modify: `Sources/Shima/IslandPanelController.swift`, `Sources/Shima/IslandView.swift`

**Interfaces:**
- Consumes: `IslandLayout.*(…, live:)` (Task 11), `HoverController.idleGeometryChanged()` (Task 12), `SpotifyService.onLiveChange` (Task 13), Spike 3's `liveFrameStrategy`.
- Produces in `IslandPanelController`:
  - `func setLive(_ live: Bool)`: ignore if unchanged; store `desiredLive`; log `live desired=<bool>`; `hover.idleGeometryChanged()`.
  - `private func applyIdleGeometry(animated: Bool)`: live start (`desiredLive && !state.live`): `setPanelFrame(expanded: false, live: true)`, then `state.live = true` (inside `withAnimation(Self.spring)` when `animated`, else in a disabled-animation transaction), then `refreshHotRect()`. Live stop (`!desiredLive && state.live`): snap `state.live = false` first, then `setPanelFrame(expanded: false, live: false)`. Otherwise `setPanelFrame(expanded: false, live: state.live)`. Use Spike 3's variant if it chose one.
  - `.shrinkPanel` → `applyIdleGeometry(animated: true)`; `.growPanel` → `setPanelFrame(expanded: true, live: state.live)`; `place(on:)` calls `applyIdleGeometry(animated: false)` after `hover.reset()` (this is 8.4's "reset re-applies the idle frame with the current live flag").
  - `setPanelFrame(expanded:live:)` logs `frame idle|expanded x=… y=… w=… h=… live=<bool>` (the M0 prefix is kept, ` live=` is appended).
  - `refreshHotRect()` uses `live: state.live`.
  - `.animateExpand` also logs `island content=<state.content>` and calls `onIslandOpened?()`.
- `IslandView`: `IslandLayout.metrics(for: state.mode, notch: notch, live: state.live)`; the notchless "invisible hot zone" fill applies only when `!state.live`.

- [ ] **Step 1: Implement per the Interfaces block**

- [ ] **Step 2: Build and run the tests**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -1`. Expected: `Build complete!`, 140 tests pass.

- [ ] **Step 3: Verify by running (AUTOMATED)**

Run: `SHIMA_FAKE_SPOTIFY=paused scripts/run.sh && sleep 2 && scripts/with-log.sh .build/t14.log -- swift scripts/drive.swift "move 735 400; fake playing; sleep 500; fake paused; sleep 500; move 735 16; sleep 700; fake playing; sleep 300; move 735 400; sleep 1500" && grep -E "frame |hover |island content" .build/t14.log | sed -E 's/^.*\] //'`
Expected: `frame idle x=613.0 y=924.0 w=245.0 h=32.0 live=true`; `frame idle x=646.0 y=924.0 w=179.0 h=32.0 live=false`; `hover collapsed -> dwelling`, `hover dwelling -> expanded`, `frame expanded x=537.5 y=783.0 w=396.0 h=173.0 …`, `island content=track`; no frame line at the toggle; after the leave: `expanded -> leaving`, `leaving -> collapsing`, `collapsing -> collapsed`, then exactly one `frame idle x=613.0 … w=245.0 … live=true`.

- [ ] **Step 4: HUMAN glance**

`SHIMA_DEBUG=1 SHIMA_FAKE_SPOTIFY=paused scripts/run.sh`; the controller toggles `fake playing`/`fake paused` five times, 1 s apart. The user confirms the red wings grow out smoothly from the notch and vanish instantly, with no flash.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shima/IslandPanelController.swift Sources/Shima/IslandView.swift
git commit -m "Apply the live idle frame only while the panel is small; widen the collapsed island"
```

---

### Task 15: Live-mode verification scripts (SCRIPT, sequential)

Criterion 6's live-frame and live-hover parts as repeatable commands.

**Files:**
- Modify: `scripts/shima-windows.swift`, `scripts/verify-alignment.sh`
- Create: `scripts/verify-live-hover.sh`

**Interfaces:**
- Produces:
  - `scripts/verify-alignment.sh [--live | --expanded | --menus]` passes its arguments (`exec swift scripts/shima-windows.swift "$@"`).
  - `shima-windows.swift`: no argument keeps M0's behavior and output exactly. `--live` expects `notch.insetBy(dx: -33, dy: 0)` and prints `PASS live frame matches notch+wings within 1pt`, then finds the first status item (the leftmost window not owned by Shima with layer 25, `y == 0` and `x >= notch.maxX`) and prints `first status item x=860` plus `PASS wings clear first status item (gap 2pt)`, or `FAIL wings overlap first status item` (exit 1). `--expanded` expects the `396 x 173` frame centred on the notch (`PASS expanded frame matches layout within 1pt`). `--menus` lists on-screen windows with layer ≥ 101 not owned by Shima as `menu window owner=<name> x=… y=… w=… h=…`, exits 0 when there is at least one, else prints `no menu window` and exits 1. Mismatches print `MISMATCH expected … window …` and exit 1, as in M0.
  - `scripts/verify-live-hover.sh`: runs sequences A-H in fake mode and prints `ok`/`FAIL` per assertion, then `PASS live hover` or `FAIL live hover` (exit 1); exits 2 with `not in fake mode` when `fake ping` is not acknowledged in the log.

- [ ] **Step 1: Extend `shima-windows.swift` and `verify-alignment.sh`**

- [ ] **Step 2: Write `scripts/verify-live-hover.sh`**

```bash
#!/usr/bin/env bash
# Criterion 6 in the live state, fake mode only (SHIMA_FAKE_SPOTIFY=paused scripts/run.sh). Hands off the mouse.
set -uo pipefail
cd "$(dirname "$0")/.."
N="735 16"; A="735 400"; W="630 16"
dir="$(mktemp -d -t shima-live)"; fail=0
d() { swift scripts/drive.swift "$1" >/dev/null; }
seq_run() { # name, prep, steps
  d "$2; move $A; sleep 1500"
  scripts/with-log.sh "$dir/$1.log" -- swift scripts/drive.swift "$3" >/dev/null
  grep -E 'frame (idle|expanded)|hover |fake ' "$dir/$1.log" > "$dir/$1.ev" || true
}
count() { grep -c -- "$2" "$dir/$1.ev" || true; }
check() { if [[ "$3" == "$4" ]]; then echo "ok   $1: $2"; else echo "FAIL $1: $2 (got $3, want $4; $dir/$1.ev)"; fail=1; fi; }
last_frame() { grep 'frame ' "$dir/$1.ev" | tail -1 | grep -oE 'w=[0-9.]+' || echo none; }

scripts/with-log.sh "$dir/ping.log" -- swift scripts/drive.swift "fake ping" >/dev/null
grep -q 'fake ping' "$dir/ping.log" || { echo "not in fake mode (SHIMA_FAKE_SPOTIFY=paused scripts/run.sh)"; exit 2; }

seq_run A "fake paused" "$(printf 'fake playing; sleep 400; fake paused; sleep 400; %.0s' 1 2 3 4 5)"
check A "idle frames" "$(count A 'frame idle')" 10;  check A "no hover" "$(count A 'hover ')" 0
seq_run B "fake paused" "move $N; sleep 700; fake playing; sleep 400; move $A; sleep 1500"
check B "one grow" "$(count B 'frame expanded')" 1;  check B "one idle frame" "$(count B 'frame idle')" 1
check B "ends live" "$(last_frame B)" "w=245.0"
seq_run C "fake playing" "move $N; sleep 700; fake paused; sleep 400; move $A; sleep 1500"
check C "one grow" "$(count C 'frame expanded')" 1;  check C "ends not live" "$(last_frame C)" "w=179.0"
seq_run D "fake paused" "move $N; sleep 30; fake playing; sleep 700; move $A; sleep 1500"
check D "one grow" "$(count D 'frame expanded')" 1;  check D "ends live" "$(last_frame D)" "w=245.0"
check D "one collapse" "$(count D '-> collapsing')" 1
seq_run E "fake paused" "move $N; sleep 150; fake playing; sleep 600; move $A; sleep 1500"
check E "one grow" "$(count E 'frame expanded')" 1;  check E "one idle frame" "$(count E 'frame idle')" 1
seq_run F "fake playing" "move $N; sleep 700; move $A; sleep 400; move $N; sleep 20; fake paused; sleep 700; move $A; sleep 1500"
check F "re-entry" "$(count F 'collapsing -> dwelling')" 1;  check F "one grow" "$(count F 'frame expanded')" 1
check F "one idle frame" "$(count F 'frame idle')" 1;  check F "ends not live" "$(last_frame F)" "w=179.0"
seq_run G "fake playing" "move $W; sleep 30; fake paused; sleep 500"
check G "shrinks" "$(count G 'frame idle')" 1;  check G "dwell cancelled" "$(count G 'dwelling -> collapsed')" 1
check G "no grow" "$(count G 'frame expanded')" 0
seq_run H "fake playing" "move $N; sleep 700; $(printf 'move 735 178; sleep 50; move 735 165; sleep 50; %.0s' $(seq 20)) move $A; sleep 1500"
check H "one collapse" "$(count H '-> collapsing')" 1;  check H "one grow" "$(count H 'frame expanded')" 1
# Timing from B's log (compact style: field 2 is hh:mm:ss.mmm).
ms() { grep -m1 -- "$2" "$dir/$1.log" | awk '{ split($2, t, ":"); printf "%d", (t[1]*3600 + t[2]*60 + t[3]) * 1000 }'; }
dwell=$(( $(ms B 'dwelling -> expanded') - $(ms B 'collapsed -> dwelling') ))
debounce=$(( $(ms B 'leaving -> collapsing') - $(ms B 'expanded -> leaving') ))
echo "dwell ${dwell} ms (want 60-150), debounce ${debounce} ms (want 280-420)"
(( dwell >= 60 && dwell <= 150 && debounce >= 280 && debounce <= 420 )) || { echo "FAIL timing"; fail=1; }
(( fail == 0 )) && echo "PASS live hover" || { echo "FAIL live hover"; exit 1; }
```
Sequence F can race (the collapse may finish before the re-entry): on a failure of F only, rerun the script once and record both runs. `chmod +x scripts/verify-live-hover.sh`.

- [ ] **Step 3: Verify by running (AUTOMATED)**

Run: `SHIMA_FAKE_SPOTIFY=paused scripts/run.sh && sleep 2 && scripts/verify-alignment.sh && swift scripts/drive.swift "fake playing" >/dev/null && sleep 1 && scripts/verify-alignment.sh --live; swift scripts/drive.swift "fake paused" >/dev/null; sleep 1; scripts/verify-live-hover.sh`
Expected: `PASS idle frame matches notch within 1pt`; `window layer=25 x=613 y=0 w=245 h=32`, `PASS live frame matches notch+wings within 1pt`, `first status item x=860`, `PASS wings clear first status item (gap 2pt)`; every sequence `ok`, dwell about 80 ms, debounce about 300 ms, `PASS live hover`.

- [ ] **Step 4: Commit**

```bash
git add scripts/shima-windows.swift scripts/verify-alignment.sh scripts/verify-live-hover.sh
git commit -m "Add live and expanded alignment modes, menu check, and live hover verification"
```

---

### Task 16: SpotifyScripting and the Apple Event client (GLUE, sequential)

8.4 "Scripting": a `final class` marked `@unchecked Sendable` with its own private serial queue, raw events by pid, 2 s timeout, results coalesced and tagged, applied only on the main actor.

**Files:**
- Create: `Sources/Shima/SpotifyScripting.swift`, `Sources/Shima/SpotifyAppleEventClient.swift`

**Interfaces:**
- Consumes: `SpotifyAppleEvents` (Task 2), `SpotifyReading`, `SpotifyCommand`, `SpotifyScriptError`, `SpotifyRequestGate` (Tasks 6, 7, 10), `SpotifyClient` (Task 9), Spike 2 decisions.
- Produces:
```swift
final class SpotifyScripting: @unchecked Sendable {   // all state confined to `queue`
    private let queue = DispatchQueue(label: "local.shima.spotify-scripting", qos: .userInitiated)
    func snapshot(pid: pid_t, completion: @escaping @Sendable (Result<SpotifyReading, SpotifyScriptError>, Date) -> Void)
    func command(_ command: SpotifyCommand, pid: pid_t, completion: @escaping @Sendable (Result<Void, SpotifyScriptError>) -> Void)
}
@MainActor final class SpotifyAppleEventClient: SpotifyClient {
    init(scripting: SpotifyScripting = SpotifyScripting())
    var onEvent: (@MainActor (SpotifyEvent) -> Void)?
    func refresh(); func send(_ command: SpotifyCommand); func invalidate()
    static func spotifyPID() -> pid_t?   // NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first { !$0.isTerminated }?.processIdentifier
}
```
`snapshot` (on `queue`): `get pPlS` → state (`kPSP` playing, `kPSp` paused, `kPSS` stopped, per Spike 2); `get pPos` → seconds; if stopped, return `SpotifyReading(state: .stopped)`; else the current track's fields per `snapshotStrategy` (`pALL` record of `pTrk`, or one `get` per property), converting `pDur` per `durationUnit`, `aUrl` through `SpotifyReading.artworkURL(from:)`, `ID  ` as `trackID`. The `Date` passed to the completion is taken right after the `pPos` reply. Errors: catch `NSError` → `SpotifyScriptError(code: error.code)`. Commands: `previous` → `spfy`/`Prev`, `playPause` → `spfy`/`PlPs`, `next` → `spfy`/`Next`. Each private helper begins with `dispatchPrecondition(condition: .onQueue(queue))`.
Client:
- `refresh()`: `guard let pid = Self.spotifyPID() else { return }` (no pid, no event, ever); `guard let t = gate.request(pid: pid) else { log "spotify refresh coalesced"; return }`; `run(t)`.
- `run(t)`: log `spotify refresh seq=<n> pid=<p>`; `scripting.snapshot(pid: t.pid) { result, date in Task { @MainActor [weak self] in self?.finished(t, result, date) } }`.
- `finished`: `let o = gate.finish(t, currentPid: Self.spotifyPID())`; log `spotify result seq=<n> applied=<bool>` (plus ` error=<code>` on failure). If `o.apply`: success → `onEvent?(.reading(r, source: .script, at: date))`; `.permissionDenied` → `onEvent?(.permissionDenied)`; `.notRunning`, `.timeout`, `.other` → log only (the workspace `didTerminate` is the authority for "not running"; a timeout waits for the next broadcast or open). Then `if let next = o.next { run(next) }`.
- `send(_:)`: pid guard as above; `let t = gate.ticket(pid: pid)`; completion on the main actor: `gate.finish(t, …)`; when it applies and the error is `.permissionDenied`, `onEvent?(.permissionDenied)`; log `spotify command result <cmd> seq=<n> ok|error=<code>`.
- `invalidate()`: `gate.invalidate()`.

- [ ] **Step 1: Implement both files per the Interfaces block**

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | grep -iE "warning|error|Compiling|Build complete" | tail -5`
Expected: `Build complete!` and no isolation or Sendable warnings.

- [ ] **Step 3: Static safety checks (AUTOMATED)**

Run: `grep -rnE 'NSAppleScript|tell application|NSAppleEventDescriptor\(bundleIdentifier|openApplication|launchApplication|NSWorkspace\.shared\.open' Sources; echo "launch-api hits: $?"; grep -rn "unchecked Sendable" Sources`
Expected: `launch-api hits: 1` (grep found nothing); the only `unchecked Sendable` line is in `Sources/Shima/SpotifyScripting.swift`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Shima/SpotifyScripting.swift Sources/Shima/SpotifyAppleEventClient.swift
git commit -m "Add SpotifyScripting (serial queue, raw events by pid) and the Apple Event client"
```

---

### Task 17: Spotify observers and real-mode wiring (GLUE, sequential)

8.4: the playback observer with `.deliverImmediately`, `userInfo` parsed in the callback; workspace launch/quit; no Apple Events on launch; one snapshot at start only if Spotify is already running.

**Files:**
- Create: `Sources/Shima/SpotifyObservers.swift`
- Modify: `Sources/Shima/SpotifyService.swift`, `scripts/run.sh`

**Interfaces:**
- Consumes: `SpotifyAppleEventClient` (Task 16), `SpotifyReading(notification:)` (Task 7).
- Produces:
  - `@MainActor final class SpotifyObservers: NSObject { init(onEvent: @escaping @MainActor (SpotifyEvent) -> Void); func start() }`. Playback: `DistributedNotificationCenter.default().addObserver(self, selector: #selector(playbackChanged(_:)), name: .init("com.spotify.client.PlaybackStateChanged"), object: nil, suspensionBehavior: .deliverImmediately)`; `@objc nonisolated func playbackChanged(_ note: Notification)` builds `let reading = SpotifyReading(notification: note.userInfo ?? [:])` and `let at = Date()` (both `Sendable`), then `MainActor.assumeIsolated { if let reading { self.onEvent(.reading(reading, source: .notification, at: at)) } }`; an unparseable payload logs `spotify broadcast unparsed`. Workspace: `NSWorkspace.shared.notificationCenter` `didLaunchApplicationNotification` → `.launched`, `didTerminateApplicationNotification` → `.terminated`, only for bundle id `com.spotify.client` (queue `.main`, `MainActor.assumeIsolated` inside).
  - `SpotifyService` real path: client `SpotifyAppleEventClient`, `client.onEvent = receive`, `SpotifyObservers(onEvent: receive).start()` **before** the running check (so a launch in between is not missed), then `let running = SpotifyAppleEventClient.spotifyPID() != nil`, log `spotify mode real running=<bool>`, and if running: `receive(.launched)`, `client.refresh()`.
  - `run.sh` guard, before `./scripts/bundle.sh`:
```bash
if [[ -z "${SHIMA_FAKE_SPOTIFY:-}" && -z "${SHIMA_SIGN_ID:-}" ]] && pgrep -x Spotify >/dev/null; then
  echo "Spotify is running: a real-mode build needs SHIMA_SIGN_ID (stable Automation grant) or SHIMA_FAKE_SPOTIFY." >&2
  exit 1
fi
```

- [ ] **Step 1: Implement**

- [ ] **Step 2: Build and test**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | tail -1`. Expected: `Build complete!`, 140 tests pass.

- [ ] **Step 3: Verify criterion 3 by running (AUTOMATED; Spotify must be quit, ask the user if `pgrep -x Spotify` prints a pid)**

Run: `pgrep -x Spotify; scripts/run.sh && sleep 2 && scripts/verify-alignment.sh && scripts/with-log.sh .build/t17.log -- swift scripts/drive.swift "move 735 400; sleep 300; move 735 16; sleep 800; click 786.5 128; sleep 300; move 735 400; sleep 1500" ; grep -E "spotify|island content" .build/t17.log | sed -E 's/^.*\] //'; /usr/bin/log show --last 2m --predicate 'subsystem == "local.shima"' | grep -cE "spotify (refresh|command)"; sleep 20; pgrep -x Spotify; echo "exit $?"`
Expected: no pid from the first `pgrep`; `PASS idle frame matches notch within 1pt`; `island content=notRunning`; no `spotify refresh` or `spotify command` lines (count `0`); no pid from the last `pgrep`, `exit 1`. The log (or `log show`) has `spotify mode real running=false`.
Also: `SHIMA_FAKE_SPOTIFY= scripts/run.sh` with Spotify running and no `SHIMA_SIGN_ID` prints the guard message and exits 1 (check only when the user has Spotify open for a HUMAN step).

- [ ] **Step 4: Smoke with real Spotify (HUMAN)**

`scripts/watch-hover.sh` open. Spotify quit. Run `SHIMA_SIGN_ID='Apple Development: jpatrickzephyr@gmail.com (<cert-id>)' scripts/run.sh` (key prompt: the user answers).
1. The user launches Spotify. Expected log: `spotify event launched`, **no** `spotify refresh`.
2. The user turns on Private Session, mutes, plays. Expected: `spotify event reading src=notification state=playing …`, `spotify live true`, one `spotify refresh seq=1 …`, `spotify result seq=1 applied=true`, `spotify event reading src=script …`. The controller runs `scripts/verify-alignment.sh --live`: PASS.
3. The user pauses: `spotify live false`; `scripts/verify-alignment.sh`: PASS (idle).
4. The user plays, then quits Spotify: `spotify event terminated`, `spotify live false`; `verify-alignment.sh` PASS idle; 20 s later `pgrep -x Spotify` prints nothing.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shima/SpotifyObservers.swift Sources/Shima/SpotifyService.swift scripts/run.sh
git commit -m "Observe Spotify broadcasts and launch/quit; wire the real Spotify client"
```

---

### Task 18: ArtworkCache (GLUE, sequential)

8.2 "Artwork": ephemeral `URLSession`, `NSCache` (`countLimit` 10), downsampled to 176 px, the in-flight fetch cancelled on a track change, stale results dropped, failure shows the placeholder and retries only on the next track. The only network access.

**Files:**
- Create: `Sources/Shima/ArtworkCache.swift`
- Modify: `Sources/Shima/SpotifyService.swift` (wire `coordinator.onArtwork`)

**Interfaces:**
- Consumes: `SpotifyCoordinator.onArtwork` (Task 9), `IslandMedia` (Task 13).
- Produces: `@MainActor final class ArtworkCache { init(media: IslandMedia); func show(trackID: String?, url: URL?) }`, plus `nonisolated static func downsample(_ data: Data, maxPixel: Int = 176) -> CGImage?` (ImageIO: `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceThumbnailMaxPixelSize: 176`, `kCGImageSourceCreateThumbnailWithTransform`, `kCGImageSourceShouldCacheImmediately`).
- Behavior of `show`: `url == nil` → cancel any task, `media.artwork = nil`, log `artwork none`. A cached URL → set it. `trackID == failedTrackID` → placeholder, no retry. Otherwise cancel the current task, remember `currentURL = url`, start `Task` that awaits `session.data(from: url)` and decodes with `downsample` off the main actor (a `nonisolated` async helper); back on the main actor, `guard url == currentURL` else log `artwork dropped stale`; on success cache it and set `media.artwork = NSImage(cgImage:size: 88x88)`, log `artwork loaded px=176 ms=<elapsed>`; on failure (not cancellation) set `failedTrackID = trackID`, placeholder, log `artwork failed code=<code>`. Start of a fetch logs `artwork load host=<host>`.
- Session: `URLSessionConfiguration.ephemeral` with `urlCache = nil`, `requestCachePolicy = .reloadIgnoringLocalCacheData`, `timeoutIntervalForRequest = 10`.

- [ ] **Step 1: Implement; wire `coordinator.onArtwork = { [weak cache] in cache?.show(trackID: $0, url: $1) }` in both fake and real paths**

- [ ] **Step 2: Build; static check**

Run: `swift build 2>&1 | tail -1 && grep -rlnE 'URLSession|URLRequest|NSURLConnection|dataTask' Sources`
Expected: `Build complete!`; the only file listed is `Sources/Shima/ArtworkCache.swift`.

- [ ] **Step 3: Verify in fake mode (AUTOMATED)**

Run: `SHIMA_FAKE_SPOTIFY=playing scripts/run.sh && sleep 2 && /usr/bin/log show --last 30s --predicate 'subsystem == "local.shima" AND category == "artwork"' | sed -E 's/^.*\] //'`
Expected: `artwork none` (fake readings carry no URL, so no network).

- [ ] **Step 4: Verify with real Spotify (HUMAN, can be folded into Task 21 Step 5 or the acceptance run)**

Signed build, Spotify playing muted in a Private Session, `scripts/watch-hover.sh` open. The user presses Next in Spotify three times quickly, then once more after 3 s. Expected: one `artwork load host=i.scdn.co` per track, `artwork dropped stale` (or cancelled loads) during the quick skips, and for the final track `artwork loaded` within 1 s of its `spotify event reading src=notification` line. The user confirms the open island and the mini artwork show the current track's cover.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shima/ArtworkCache.swift Sources/Shima/SpotifyService.swift
git commit -m "Add artwork cache: ephemeral session, 176 px downsample, stale results dropped"
```

---

### Task 19: Wings view (GLUE, sequential)

8.2 live state: left wing 20x20 mini artwork (radius 5), right wing the equalizer (Spike 5's frame rate), both vertically centred in the 32 pt strip.

**Files:**
- Create: `Sources/Shima/WingsView.swift`
- Modify: `Sources/Shima/IslandView.swift`, `Sources/Shima/IslandPanelController.swift` (pass `media`)

**Interfaces:**
- Consumes: `EqualizerView` (Task 5), `NowPlayingLayout` wing constants (Task 11), `IslandMedia`, `AppState.live`.
- Produces: `struct WingsView: View { let state: AppState; let media: IslandMedia; let notchWidth: CGFloat }`, laid out as an `HStack(spacing: 0)` of `[left wing 33 | Color.clear notchWidth | right wing 33]`, `.frame(width: notchWidth + 66, height: 32)`, top-centred in the island `ZStack`. Left: `media.artwork` as `Image(nsImage:)` `.resizable().aspectRatio(contentMode: .fill)` or the placeholder (`RoundedRectangle` filled `Color.white.opacity(0.18)` with `Image(systemName: "music.note")` at 10 pt, white 0.6), clipped to radius 5, 20x20. Right: `EqualizerView(animating: animating)` 16x14.
  - `animating = state.live && state.mode == .collapsed && state.nowPlaying?.state == .playing && !media.equalizerFrozen`.
  - The wings view is **always** in the hierarchy (stable identity for the `NSViewRepresentable`); visibility is `.opacity(state.live && state.mode == .collapsed ? 1 : 0)` and `.allowsHitTesting(false)`.
- `IslandView` gains `media: IslandMedia` and draws `WingsView` above the island shape.

- [ ] **Step 1: Implement**

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -1`. Expected: `Build complete!`.

- [ ] **Step 3: HUMAN look**

`SHIMA_FAKE_SPOTIFY=playing scripts/run.sh`. The user compares the wings with `mockup/index.html` (`.slot`, `.mini-art`, `.wave`): placeholder artwork on the left, four green bars moving on the right, both centred, nothing touching the status item. Decide: green `#1ED760` or white (8.2: "white if green looks loud"); if white, set `EqualizerNSView.tint = .white` and record the choice in the commit message.

- [ ] **Step 4: Lifecycle by running (AUTOMATED)**

Run: `scripts/with-log.sh .build/t19.log -- swift scripts/drive.swift "move 735 400; sleep 500; fake paused; sleep 400; fake playing; sleep 400; move 735 16; sleep 800; move 735 400; sleep 1500; fake eq-frozen; sleep 300; fake eq-animating; sleep 300; fake quit; sleep 400; fake launch; sleep 200; fake playing; sleep 600" && grep -E "eq |spotify live" .build/t19.log | sed -E 's/^.*\] //'`
Expected, in order: `eq frozen anims=0` (pause; wings snap away), `eq animating anims=4` (play), `eq frozen anims=0` (expanded), `eq animating anims=4` (collapsed again), `eq frozen anims=0`, `eq animating anims=4` (A/B knob), `eq frozen anims=0` (quit), `eq animating anims=4` (play after relaunch). Never `anims=8`; no duplicate consecutive lines.

- [ ] **Step 5: Commit**

```bash
git add Sources/Shima/WingsView.swift Sources/Shima/IslandView.swift Sources/Shima/IslandPanelController.swift Sources/Shima/EqualizerView.swift
git commit -m "Show mini artwork and the equalizer in the live wings"
```

---

### Task 20: Open-island now-playing view (GLUE, sequential)

8.2 open island: artwork, title, artist, progress bar with elapsed/remaining, and the status texts. Buttons are drawn in Task 21.

**Files:**
- Create: `Sources/Shima/NowPlayingView.swift`
- Modify: `Sources/Shima/IslandView.swift` (replace the "shima" placeholder text)

**Interfaces:**
- Consumes: `NowPlayingLayout` (Task 11), `AppState.content`/`nowPlaying`/`mode`, `IslandMedia.artwork`, `PlaybackTime`, `NowPlaying.position(at:)`.
- Produces: `struct NowPlayingView: View { let state: AppState; let media: IslandMedia }`, `.frame(width: 360, height: 165)`, top-centred in the island `ZStack`, children placed by `NowPlayingLayout` rects (`.frame` + `.position` in island-local y-down coordinates). Opacity 1 when expanded, else 0 (the M0 cross-fade).
  - `.track`: artwork 88x88 radius 10 (`media.artwork` or the placeholder at 88 px); title 15 pt semibold white, one line, truncating tail; artist 12.5 pt white 0.6; progress bar 4 pt (track `Color.white.opacity(0.18)`, fill white, width = `PlaybackTime.fraction`), times 11 pt `.monospacedDigit()` white 0.45, elapsed left, remaining right.
  - Progress: **only** `if state.mode == .expanded && np.state == .playing` build `TimelineView(.periodic(from: .now, by: 1)) { ctx in progressRow(np, at: ctx.date) }` and inside it `let _ = Log.spotify.debug("progress tick")`; otherwise `progressRow(np, at: Date())`. Never keep a `TimelineView` in the hierarchy while collapsed or paused.
  - `.notRunning`: centred `Text("Spotify is not running")`, 13 pt, white 0.6.
  - `.permissionDenied`: centred two lines: `Text("shima can't control Spotify")` 13 pt white 0.85 and `Text("Allow it in System Settings › Privacy & Security › Automation")` 11.5 pt white 0.5.
  - `.nothingPlaying`: centred `Text("Nothing playing")`, 13 pt, white 0.6.

- [ ] **Step 1: Implement**

- [ ] **Step 2: Build; static check**

Run: `swift build 2>&1 | tail -1 && grep -rn "TimelineView" Sources`
Expected: `Build complete!`; `TimelineView` appears only in `Sources/Shima/NowPlayingView.swift`.

- [ ] **Step 3: HUMAN look**

`SHIMA_FAKE_SPOTIFY=playing scripts/run.sh`; the user hovers the notch. Compare with the mockup's now-playing panel (`renderMusic`, scaled to 360x165): placeholder artwork, "Fake Track One", "shima fake", a moving progress bar, times ticking. 8.2: if it looks cramped, the user decides whether the island height grows (if yes, that is a change to `IslandLayout.expanded` and `NowPlayingLayout` with their tests, and a new task).

- [ ] **Step 4: Content kinds by running (AUTOMATED)**

Run: `scripts/with-log.sh .build/t20a.log -- swift scripts/drive.swift "move 735 400; fake playing; sleep 300; move 735 16; sleep 800; move 735 400; sleep 1500; fake quit; sleep 300; move 735 16; sleep 800; move 735 400; sleep 1500; fake launch; sleep 300; move 735 16; sleep 800; move 735 400; sleep 1500; fake playing; sleep 300" && grep "island content" .build/t20a.log | sed -E 's/^.*\] //'`
Expected: `island content=track`, `island content=notRunning`, `island content=nothingPlaying`.

- [ ] **Step 5: Progress ticks only while open and playing (criterion 5, AUTOMATED)**

Run: `scripts/with-log.sh .build/t20b.log -- swift scripts/drive.swift "fake playing; move 735 400; sleep 5000; fake ping; move 735 16; sleep 5000; fake paused; sleep 4000; fake ping; move 735 400; sleep 1500; fake playing; sleep 5000"`; then count `progress tick` lines between markers:
`awk '/fake ping/{p++} /progress tick/{c[p]++} END{print "collapsed:", c[0]+0, "open+playing-then-paused:", c[1]+0, "collapsed again:", c[2]+0}' .build/t20b.log`
Expected: `collapsed: 0`, the open segment has 4-6 ticks all before the `fake paused` line (check `grep -n -E "fake paused|progress tick" .build/t20b.log`: no tick after `fake paused` while still open), `collapsed again: 0`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Shima/NowPlayingView.swift Sources/Shima/IslandView.swift
git commit -m "Add the open-island now-playing view with a progress bar that ticks only while open and playing"
```

---

### Task 21: Controls on a first-mouse hosting view (GLUE, sequential)

8.2 "Clicks": the three buttons work; everything else ignores clicks; a click never activates Shima or Spotify.

**Files:**
- Create: `Sources/Shima/ClickHostingView.swift`
- Modify: `Sources/Shima/NowPlayingView.swift`, `Sources/Shima/IslandView.swift`, `Sources/Shima/IslandPanelController.swift`, `Sources/Shima/AppDelegate.swift`

**Interfaces:**
- Consumes: Spike 4's `clickStrategy`, `NowPlayingLayout.controlRect(_:)`, `SpotifyService.perform(_:)`.
- Produces:
  - `final class ClickHostingView<Content: View>: NSHostingView<Content>` with `override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }` (and, only if Spike 4 chose `appKitHitTest`, a `mouseDown` override that hit-tests the control rects). `IslandPanelController.hostingView` becomes `ClickHostingView<IslandView>`.
  - `NowPlayingView` gains `let onCommand: @MainActor (SpotifyCommand) -> Void`; in `.track` content, three `Button { onCommand(c) } label: { Image(systemName:) }` with `.buttonStyle(.plain)`, symbols `backward.fill`, `play.fill`/`pause.fill` (by `np.state`), `forward.fill`, white, at `controlRect(c)`; play/pause on a `Circle().fill(Color.white.opacity(0.12))` 32 pt; previous/next 28 pt hit areas (`.contentShape(Circle())`). The whole content has `.allowsHitTesting(state.mode == .expanded && state.content == .track)`.
  - `IslandPanelController`: `var onCommand: (@MainActor (SpotifyCommand) -> Void)?`; its handler logs `spotify command <cmd> active=\(NSApp.isActive) key=\(panel.isKeyWindow)` and forwards. `AppDelegate` wires `islandController.onCommand = { [weak self] in self?.spotify.perform($0) }`.

- [ ] **Step 1: Implement**

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -1`. Expected: `Build complete!`.

- [ ] **Step 3: Clicks reach the fake client (AUTOMATED)**

Run: `SHIMA_FAKE_SPOTIFY=playing scripts/run.sh && sleep 2 && scripts/with-log.sh .build/t21.log -- swift scripts/drive.swift "move 735 400; sleep 300; move 735 16; sleep 700; click 830.5 128; sleep 400; click 786.5 128; sleep 400; click 742.5 128; sleep 400; click 600 60; sleep 300; move 735 400; sleep 1500" && grep -E "spotify (command|event reading)|became active" .build/t21.log | sed -E 's/^.*\] //'`
Expected: `spotify command next active=false key=false`, `… reading … track=fake:2`; `spotify command playPause active=false key=false`, `… state=paused …`; `spotify command previous active=false key=false`, `… track=fake:1`; nothing for the artwork click; no `app became active`.

- [ ] **Step 4: Focus (AUTOMATED)**

Repeat Step 3's drive line with `before`/`after` from `lsappinfo info -only name "$(lsappinfo front)"` around it (Terminal frontmost). Expected: `before == after`, not `Shima`. Task 22 turns this into `verify-focus.sh --clicks`.

- [ ] **Step 5: Real Spotify (HUMAN)**

Signed build, Spotify playing muted in a Private Session, `scripts/watch-hover.sh` open. The user hovers, clicks next, previous, play/pause twice; Spotify follows each click; the open island updates title, artist, artwork and the play/pause symbol; Spotify does not come to the front. Then the user changes track and pauses inside Spotify; the island follows (criterion 2).

- [ ] **Step 6: Commit**

```bash
git add Sources/Shima/ClickHostingView.swift Sources/Shima/NowPlayingView.swift Sources/Shima/IslandView.swift Sources/Shima/IslandPanelController.swift Sources/Shima/AppDelegate.swift
git commit -m "Add previous, play/pause and next buttons on a first-mouse hosting view"
```

---

### Task 22: `verify-focus.sh --clicks` (SCRIPT, sequential)

Criterion 6 "focus never stolen with real button clicks".

**Files:**
- Modify: `scripts/verify-focus.sh`

**Interfaces:**
- Produces: `scripts/verify-focus.sh [secs]` keeps M0's manual mode unchanged. `scripts/verify-focus.sh --clicks` (fake mode required) is hands-off: records the frontmost app, captures the log while `drive.swift` hovers, clicks previous, play/pause, next and the artwork point, and leaves; then checks: `fake ping` acknowledged (else exit 2, `not in fake mode`), exactly 3 `spotify command … active=false key=false` lines, no `active=true` or `key=true`, no `app became active`, frontmost unchanged and not `Shima`, `pgrep -x Shima` still prints a pid. Prints `PASS clicks: 3 commands, frontmost unchanged: <app>` or `FAIL <reason>` (exit 1).

- [ ] **Step 1: Add the `--clicks` branch**

Drive line: `fake ping; fake playing; move 735 400; sleep 500; move 735 16; sleep 700; click 742.5 128; sleep 400; click 786.5 128; sleep 400; click 830.5 128; sleep 400; click 600 60; sleep 300; move 735 400; sleep 1500` (centres from `controlCentersOnThisMac`, Task 11).

- [ ] **Step 2: Verify by running (AUTOMATED)**

Run (Terminal frontmost): `SHIMA_FAKE_SPOTIFY=playing scripts/run.sh && sleep 2 && scripts/verify-focus.sh --clicks`
Expected: `PASS clicks: 3 commands, frontmost unchanged: Terminal`.

- [ ] **Step 3: Commit**

```bash
git add scripts/verify-focus.sh
git commit -m "verify-focus: hands-off mode with real button clicks in fake mode"
```

---

### Task 23: `verify-idle.sh` strict and `--playing` A/B (SCRIPT, sequential)

Criterion 7: strict 0.0% when Spotify is not playing; with Spotify playing and the island collapsed, Shima ≤ 0.1% average and WindowServer (animating − frozen) ≤ about 1.5%; the static check flags `repeatCount` and similar with a file allowlist.

**Files:**
- Modify: `scripts/verify-idle.sh`

**Interfaces:**
- Produces:
  - Static check (both modes): `grep -rnE 'addGlobalMonitorForEvents|addLocalMonitorForEvents|scheduledTimer|(^|[^A-Za-z])Timer[(.]|CVDisplayLink|CADisplayLink|displayLink|repeatForever|repeatCount|TimelineView' Sources/Shima Sources/ShimaCore`, minus lines matching `^Sources/Shima/EqualizerView\.swift:[0-9]+:.*repeatCount` and `^Sources/Shima/NowPlayingView\.swift:[0-9]+:.*TimelineView`. Any remaining hit fails.
  - Pre-check: `swift scripts/shima-windows.swift --live` succeeds → the island is live. Strict mode requires not live (else `the island is live (Spotify playing); use --playing`, exit 2); `--playing` requires live (else `the island is not live; start with SHIMA_FAKE_SPOTIFY=playing`, exit 2).
  - Strict (default): M0's 60 s measurement unchanged (CPU ≤ 0.030 s in 60 s, RSS < 60 MB, `top`, `sample` with no timer callbacks), ends `PASS idle`.
  - `--playing`: requires a `fake ping` acknowledgement (else prints `not in fake mode: reporting Shima CPU only` and runs one 60 s Shima measurement against ≤ 0.060 s, useful with real Spotify). In fake mode: two rounds of `eq-animating` then `eq-frozen`, each phase `${SHIMA_AB_SECONDS:-30}` s after a 3 s settle, measuring Shima and WindowServer (`pgrep -x WindowServer`) CPU seconds with `ps -o time=` (or Spike 5's fallback). Restores `eq-animating`. Prints:
```
Shima animating: 0.0xx% (pass <= 0.100)
Shima frozen: 0.0xx% (pass <= 0.050)
WindowServer animating - frozen: x.xxx% (pass <= 1.500)
sample: no timer callbacks
PASS playing
```
  Fails (exit 1) when a limit is exceeded, but always prints the numbers.

- [ ] **Step 1: Rewrite the script per the Interfaces block** (keep M0's helper functions `secs` and the `sample` block; add `pct` and the phase loop).

- [ ] **Step 2: Verify by running (AUTOMATED; pointer away and still, nothing else animating)**

1. `SHIMA_FAKE_SPOTIFY=paused scripts/run.sh && sleep 5 && scripts/verify-idle.sh` → `PASS idle`.
2. With Spotify quit: `scripts/run.sh && sleep 5 && scripts/verify-idle.sh` → `PASS idle`.
3. `SHIMA_FAKE_SPOTIFY=playing scripts/run.sh && sleep 5 && scripts/verify-idle.sh --playing` → the four lines above and `PASS playing` (record the numbers even if it fails).
4. Static check self-test: `echo 'let a = Timer(' > Sources/Shima/Tmp.swift; scripts/verify-idle.sh | head -3; rm Sources/Shima/Tmp.swift` → shows the hit and `FAIL static check`.

- [ ] **Step 3: Commit**

```bash
git add scripts/verify-idle.sh
git commit -m "verify-idle: strict mode, live A/B in fake mode, allowlisted repeating animations"
```

---

### Task 24: Automation permission persistence and denial (HUMAN)

Criterion 8 and 8.2 "Permission". No code unless something fails.

**Files:**
- Modify: `docs/superpowers/spikes/2026-11-21-m1-spikes.md` (a short `## Permission check` section)

- [ ] **Step 1: Stable identity (AUTOMATED part)**

Run: `SHIMA_SIGN_ID='Apple Development: jpatrickzephyr@gmail.com (<cert-id>)' scripts/bundle.sh | tail -2 && codesign -dr - dist/Shima.app 2>&1 | tail -1 && codesign -dvv dist/Shima.app 2>&1 | grep -E "Authority=Apple Development|Identifier="`
Expected: `signed with: Apple Development: …`, `Built dist/Shima.app`; a `designated =>` line with `certificate leaf[subject.CN] = "Apple Development: jpatrickzephyr@gmail.com (<cert-id>)"` and no `cdhash`; `Identifier=local.shima`. (The key prompt may appear: HUMAN.)

- [ ] **Step 2: Grant survives a rebuild (HUMAN)**

Spotify running (muted Private Session, paused is fine). Make a trivial rebuild (`touch Sources/Shima/main.swift`), then `SHIMA_SIGN_ID=… scripts/run.sh`. The user hovers the island. Expected: no Automation prompt; log `spotify result seq=… applied=true` with no `error=-1743`; `island content=track`.

- [ ] **Step 3: Denial and recovery (HUMAN)**

1. The user opens System Settings › Privacy & Security › Automation › Shima and turns off Spotify.
2. The user hovers the island. Expected: `spotify result … error=-1743`, `spotify event permissionDenied`, the open island shows "shima can't control Spotify" and the instruction (`island content=permissionDenied`). No retry happens while the pointer stays away (check: no `spotify refresh` lines for 30 s with Spotify paused and untouched).
3. The user turns Spotify back on for Shima, then hovers again. Expected: `spotify event reading src=script …`, `spotify changes [availabilityChanged(running)…]`, `island content=track`.

- [ ] **Step 4: Record and commit**

Add `## Permission check` (date, results of Steps 1-3, the identity's expiry date from `security find-certificate -c "Apple Development: jpatrickzephyr@gmail.com" -p | openssl x509 -noout -enddate`, read-only). Note: when it expires, Automation must be granted again.
```bash
git add docs/superpowers/spikes/2026-11-21-m1-spikes.md
git commit -m "Record Automation permission persistence and denial checks"
```

---

### Task 25: M1 acceptance run (ACCEPTANCE)

Run every check against a fresh build and record the results in `docs/superpowers/m1-acceptance.md`: one row per criterion with PASS/FAIL/PARTIAL, how the evidence was gathered (AUTOMATED or HUMAN), and notes. Then re-check the M0 criteria that M1 could have broken.

**Files:**
- Create: `docs/superpowers/m1-acceptance.md`

- [ ] **Step 1: Fresh build and tests**

Run: `swift test 2>&1 | tail -1 && scripts/bundle.sh | tail -1`
Expected: starts with `✔ Test run with 140 tests in 14 suites passed` (plus any spike-driven tests); `Built dist/Shima.app`.

- [ ] **Step 2: Run the checklist**

Keep `scripts/watch-hover.sh` open in a second terminal. "Signed" means `SHIMA_SIGN_ID='Apple Development: jpatrickzephyr@gmail.com (<cert-id>)'`. Real-Spotify rows are HUMAN, in a muted Private Session.

| # | Criterion | How to verify | Kind | Expected result |
|---|---|---|---|---|
| 1 | Track, artist, artwork within 1 s | Signed `scripts/run.sh`; the user presses Next in Spotify 5 times, 3 s apart, with the island open for two of them and collapsed for the others; the controller compares log timestamps | HUMAN | For each change: `spotify event reading src=notification … track=<new>` and `artwork loaded` ≤ 1 s later; the user sees the new title, artist and cover in the open island and the new mini artwork in the wings |
| 2 | Controls, and following Spotify | (a) `SHIMA_FAKE_SPOTIFY=playing scripts/run.sh && scripts/verify-focus.sh --clicks`. (b) Signed run: the user clicks previous, play/pause, next in the island; then changes track and pauses inside Spotify | AUTOMATED (a), HUMAN (b) | (a) `PASS clicks: 3 commands …` and the fake track/state changes in the log. (b) Spotify follows each click; the island follows changes made in Spotify (log + eyes) |
| 3 | Spotify quit | Spotify quit (`pgrep -x Spotify` empty): Task 17 Step 3 command; plus the static grep of Task 16 Step 3 | AUTOMATED | `PASS idle frame matches notch`, `island content=notRunning` ("Spotify is not running" in the view), zero `spotify refresh`/`spotify command` lines, `pgrep -x Spotify` empty after 20 s, `launch-api hits: 1` |
| 4 | Live indicator on play, gone on pause/stop/quit | (a) Fake: `fake playing` → `verify-alignment.sh --live`; `fake paused` → `verify-alignment.sh`; `fake playing; fake quit` → `verify-alignment.sh`. (b) Signed run: the user plays, pauses, plays, quits Spotify; the controller runs the matching `verify-alignment.sh` mode after each | AUTOMATED (a), HUMAN (b) | `PASS live frame matches notch+wings`, `PASS wings clear first status item (gap 2pt)` while playing; `PASS idle frame matches notch` after pause, stop and quit; `spotify live true/false` lines match |
| 5 | Progress ticks only while open and playing | Task 20 Step 5 command and awk count; Task 23 `--playing` sample line | AUTOMATED | 0 ticks collapsed, 4-6 ticks in 5 s open+playing, 0 after pause, 0 collapsed again; `sample: no timer callbacks` |
| 6 | M0 behaviors in the live state | `SHIMA_FAKE_SPOTIFY=paused scripts/run.sh`: `scripts/verify-live-hover.sh`; `scripts/verify-focus.sh --clicks`; live menu bar: `swift scripts/drive.swift "fake playing; sleep 500; click 872 16; sleep 500" && scripts/verify-alignment.sh --menus; swift scripts/drive.swift "key esc"`; `scripts/verify-alignment.sh --live`; plus HUMAN: the user types in TextEdit while the controller runs `verify-focus.sh --clicks` with TextEdit frontmost, and watches the wings and the open/close for flicker | AUTOMATED + HUMAN | `PASS live hover` (dwell ≈ 80 ms, debounce ≈ 300 ms, no `collapsing` loop, one frame change per transition); `PASS clicks …`; a `menu window owner=…` line (the status item at x 860+ opened its menu while live); `PASS live frame …`; typing continues in TextEdit; no flicker seen |
| 7 | CPU | `SHIMA_FAKE_SPOTIFY=paused` → `scripts/verify-idle.sh`; Spotify quit, plain `scripts/run.sh` → `scripts/verify-idle.sh`; `SHIMA_FAKE_SPOTIFY=playing` → `scripts/verify-idle.sh --playing`. Optional HUMAN: signed run with real Spotify playing muted, `scripts/verify-idle.sh --playing` (Shima-only, includes the real broadcast rate) | AUTOMATED (+ optional HUMAN) | `PASS idle` twice (static check ok, ≤ 0.030 s CPU in 60 s); `PASS playing` with Shima ≤ 0.100%, WindowServer delta ≤ 1.500%; numbers recorded as measured, even if worse |
| 8 | Automation permission survives a rebuild | Task 24 Steps 1-2 | AUTOMATED (DR) + HUMAN | Certificate-based designated requirement (no `cdhash`); no prompt after a rebuild; no `-1743` |

M0 regressions (record PASS/FAIL in a second table): criterion 1 (`scripts/verify-alignment.sh`, not live), 3 and 4 (`scripts/verify-live-hover.sh` sequences B and H cover dwell, collapse and wiggle), 5 (one `frame expanded` / one `frame idle` per hover in the log), 6 (`scripts/verify-focus.sh` manual mode with TextEdit, as in M0), 7 (Apple menu while idle and while open, as in M0), 10 (= criterion 7 strict), 11 (Quit from the status menu, if its icon is visible).

- [ ] **Step 3: Record and commit**

Write `docs/superpowers/m1-acceptance.md`: date, macOS and Spotify versions, Swift version, build commit, the spike decisions in force (`payloadComplete`, `ratePlaying`, `seekPosts`, `snapshotStrategy`, `liveFrameStrategy`, `clickStrategy`, `eqFrameRate`, equalizer colour), both tables with a result column, how evidence was gathered (CGEvent, log, window list; no screen recording), and every failure or partial with its follow-up.
```bash
git add docs/superpowers/m1-acceptance.md
git commit -m "Record M1 acceptance results"
```

---

## Plan notes / deviations

Places where the plan makes a call, or where section 8 is ambiguous, inconsistent with the M0 code, or slightly wrong. None of them was settled silently; each is listed for the reviewer and the user.

1. **`SpotifyModel.apply` returns `(NowPlaying?, [SpotifyChange])` (8.4), but the UI needs more than `NowPlaying?`.** "Spotify is not running", "permission denied" and "nothing playing" cannot be told apart from `nil`. The plan keeps the signature and adds `availability`, `content` (`NowPlayingContent`) and `isLive` on the model, and a third change, `.availabilityChanged`. `SpotifyChange.stateChanged` carries the new state (`PlaybackState?`) instead of no payload.
2. **`HoverController` needs a public `idleGeometryChanged()`.** 8.4 names only the machine input. Also, "`reset()` re-applies the idle frame with the current live flag": the machine's `reset` emits `shrinkPanel` only when the panel is large, so the re-apply when small is done by the glue in `place(on:)` (`applyIdleGeometry(animated: false)` after `hover.reset()`), not by the machine. The machine is unchanged for `reset`.
3. **A consequence of "the live flag changes only while the panel is small" that 8.4 does not mention.** If Spotify pauses or quits while the island is open, the collapse lands on the live (wide) shape with frozen bars, and the wings snap away only after the collapse completes. If Spotify starts while open, the collapse lands on the bare notch and the wings grow right after. The plan follows the spec. The alternative is to also sync the flag at the start of a collapse (`animateCollapse`), which is not "in flight", but it adds a second sync point; it is the user's call after seeing Task 14.
4. **Hot rect while live (8.2/8.4 silent).** My call: the idle hot rect is the whole live frame, so hovering a wing expands the island. Spike 3 case 5 records that turning live on with the pointer just beside the notch then expands the island.
5. **The left wing (x 613-646) can cover the frontmost app's menu titles** when an app's menus reach that far. 8.2 only checks the right side (the status item at 860). Section 2's anti-goal wording accepts the wings, so no change, but the acceptance run notes it.
6. **Broadcasts while Spotify is not running are ignored** (a "Stopped" broadcast can arrive after `didTerminate`). 8.4 is silent. `launched` only marks Spotify running; it never sends an Apple Event (8.4).
7. **Fake mode has a control channel** (distributed notification `local.shima.fake-spotify`, objects `ping`, `playing`, `paused`, `next`, `previous`, `quit`, `launch`, `eq-frozen`, `eq-animating`), honoured only in fake mode. 8.4 names only the env flag, but toggling during hover (Spike 3, `verify-live-hover.sh`) and the A/B freeze (criterion 7) need it. Any unknown non-empty `SHIMA_FAKE_SPOTIFY` value means fake paused, never real Spotify.
8. **`codesign --timestamp=none`.** With a real identity codesign may contact Apple's timestamp server; section 2 allows only the artwork request, so the plan disables it. Not in the spec.
9. **Bundle signing moved into Spike 2** (kept change) instead of a separate later task, so the very first Automation grant goes to the stable identity and is attributed to Shima rather than to the terminal. `run.sh` refuses an ad-hoc real-mode build while Spotify is running (Task 17), because an ad-hoc build would create a second, cdhash-based TCC entry. Forgetting `SHIMA_SIGN_ID` otherwise silently loses the grant.
10. **8.2 writes `TimelineView(.periodic(by: 1))`**; the API is `TimelineView(.periodic(from: .now, by: 1))`.
11. **Equalizer re-add after `orderOut`/`orderFront`:** done through `viewDidMoveToWindow` plus `NSWindow.didChangeOcclusionStateNotification`, which also pauses the bars while the display sleeps. 8.4 does not say how.
12. **Spikes first, but Spike 3 needs the machine input.** Spike 3 adds a throwaway version of `.idleGeometryChanged` and reverts it; Task 12 then implements it test-first with whatever rule the spike confirmed. Spike 2 and Spike 5 keep code (`SpotifyAppleEvents.swift`, `EqualizerView.swift`, `drive.swift`) because the spike exists to validate exactly that code; M0's spikes kept only scripts.
13. **Criterion 7's A/B is fake-mode only** (freezing the bars needs the control channel). With real Spotify the script measures Shima alone, which also includes the real broadcast rate; that run is optional and HUMAN.
14. **While permission is denied** the open island shows the instruction instead of the track, the buttons are not shown, and commands are not sent; retries happen only on the next broadcast or island open (8.2). Broadcasts still drive the live indicator, because they need no permission.
15. **A first Automation prompt can make the first events time out (-1712).** The plan does not retry on a timer (8.2), so right after the user clicks Allow nothing changes until the next broadcast or island open. Spike 2 records the actual behavior.
16. **Open-island layout:** 8.2 fixes the artwork and the right column but not the controls' y. My call: controls row y 112-144, centred in the column, 14 pt gaps, below the artwork's bottom edge (132), so the column runs to y 144. The status texts ("Nothing playing", the permission instruction) are my wording; "Spotify is not running" is the spec's.
17. **Spotify commands in spikes and checks are HUMAN-run** (a play/pause or next would play music on the user's account), even though they could be scripted.
18. **Spike 5 measures the equalizer on a separate throwaway panel at the right-wing position**, not inside the island; Task 23 re-measures inside the island in fake mode.
19. **Doc drift, no action:** section 3's Signing row and 7 #5 say "self-signed certificate", superseded by 8.1 #9 (existing Apple Development identity); `CLAUDE.md` says Swift 6.1, the toolchain is 6.4.2 (`swift-tools-version:6.0`).
20. **The status icon can still be hidden on a full menu bar** (M0 finding), so Quit may only be reachable with `pkill -x Shima`; a menu from the island is out of scope (8.7).
