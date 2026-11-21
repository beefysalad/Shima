# shima: scope and design (POC)

2026-11-20, revised 2026-11-21. Status: **awaiting approval**. (The file name keeps "notch" so CLAUDE.md's link still works; the product is shima.)

Tags used below: **[You]** = decided by the user. **[My call]** = Claude's decision, open to correction. **[Verified]** = checked against Apple/Anthropic docs or on this Mac. **[Unverified]** = assumed, with the phase that will test it.

## 1. Intent

A personal, free "Dynamic Island" for the MacBook notch, replacing a NotchBox subscription. It is built for one person's day: Claude Code sessions running in kaze or any other terminal, Spotify playing, and files moving around. The notch is dead space that is always visible. Making it the place that answers "does any Claude session need me?" and "what's playing?" without a window switch is the whole point. It is a POC: small, local, hackable, not a product. Nothing needs an API key or an account **[You]**.

## 2. Goals, non-goals, anti-goals

**Goals**
- An island flush with the notch that expands on hover and collapses without fuss, and feels native on the built-in display.
- Glanceable Claude Code state per session (running / needs you / done); one click jumps to that terminal.
- Spotify now playing, with artwork and controls.
- A file shelf: drop files on the island, drag them back out, AirDrop them.
- Automations from one human-editable config file.

**Non-goals (POC):** system-wide Now Playing (MediaRemote is restricted), Apple Music, camera mirror, widgets, themes, distribution or notarization, other users, Windows or Linux, showing on external monitors **[You]**, approving Claude permission requests from the island **[You]**.

**Anti-goals (must never happen)**
| Anti-goal | Guard |
|---|---|
| CPU use while idle | No timers or polling when collapsed; event-driven only. Target 0.0% CPU idle. **Exception [You, 2026-11-21]:** while Spotify is playing, the collapsed live indicator's equalizer animates continuously (budget in section 8). The rule is unchanged whenever Spotify is not playing |
| Accounts or API keys | None. The only network request is Spotify artwork from its CDN **[You]** |
| Flicker or jitter at the notch | One persistent panel; animate content, never recreate windows |
| Stealing focus from the active app | Non-activating panel; see 6.4 |
| Slowing Claude Code down | `shimactl` always exits 0 within 1 s, even when the app is not running |
| Blocking clicks on the menu bar | While idle the panel covers only the notch strip, plus the live wings (33 pt each side, clear of the status items) while Spotify plays; it grows only while expanded |

## 3. Constraints

| Item | Decision |
|---|---|
| OS | macOS 26 on Apple Silicon (dev machine); deployment target 14.0 (for `UnevenRoundedRectangle`, `@Observable`) |
| Toolchain | **SwiftPM only, no `.xcodeproj`** **[You]**. Everything builds with `swift build`. Xcode 27.2 is now installed (it was not when this was decided), but the SwiftPM-only choice stands. The scaffold was built with Swift 6.1 from the Command Line Tools; re-check the toolchain version after the Xcode license is accepted |
| Dependencies | None third-party without asking **[You]** |
| UI | SwiftUI views in one borderless non-activating `NSPanel` **[You]** |
| Sandbox | Off **[My call]**: Unix socket, `~/.claude` reads, shell actions and Apple Events to Spotify are awkward inside the sandbox, and a personal app gains nothing from it |
| Hardened runtime | **Not enabled for now [My call]**. The current `bundle.sh` does not enable it. It only matters if we turn it on, which needs the `apple-events` entitlement in M1. Revisit in M1 |
| Signing | M0: ad-hoc (`codesign -s -`), as scaffolded. **M1: an existing Apple Development identity from the login keychain [You], via `SHIMA_SIGN_ID`, for a stable identity (see 8.4)**, so Spotify automation permission survives rebuilds. No new keychain entry is created |
| Automation (TCC) | Once for Spotify (`NSAppleEventsUsageDescription` in Info.plist, added in M1). Later maybe System Events or Terminal/iTerm |
| Accessibility | Not needed in the POC. Carbon `RegisterEventHotKey` hotkeys and `NSTrackingArea` hover need none |
| Files | Shelf in `~/Library/Application Support/Shima/Shelf/`. Socket at `~/Library/Application Support/Shima/shima.sock` |
| Config | `~/.config/shima/config.json` **[You]** (JSON, no third-party parser; no comments, so use a `"note"` field) |
| Autostart | `SMAppService.mainApp.register()` toggled from the status menu. **[Unverified]** with an ad-hoc-signed app run from `dist/`; tested in M0 |
| Background | `LSUIElement = YES`. Status-bar menu: Quit, Launch at login (later Reload config) |
| Bundle id | `local.shima` |

## 4. Approaches

### 4.1 UI stack
SwiftUI in one AppKit `NSPanel` **[You]**. AppKit-heavy views (2 to 3x the code) and pure-SwiftUI scenes (cannot get a non-activating, menu-bar-level, borderless panel) were rejected.

### 4.2 Claude Code event transport
Unix domain socket **[My call]**: instant, no port or token, file permissions (0600) protect it, trivially "down" when the app is not running. File-drop + FSEvents (latency, ordering) and loopback HTTP (port, token, open listener) were rejected.

Client: `shimactl` (already scaffolded, Swift, bundled in `Shima.app/Contents/MacOS/`). A hook runs `shimactl hook <event>`. It reads the hook JSON from stdin, adds `ppid`, `tty`, `TERM_PROGRAM` and `__CFBundleIdentifier` from its environment (hooks inherit the parent environment **[Verified]**), writes one JSON line to the socket, 500 ms timeout, always exits 0. Hooks are added next to the existing `kaze notify` hooks; that edit to `~/.claude/settings.json` is the user's to make, never done by Claude.

**Hook payload [Verified against code.claude.com/docs/en/hooks]:** every event has `session_id`, `transcript_path`, `cwd`, `hook_event_name` (plus optional `permission_mode`, `prompt_id`). Notification adds `message`, optional `title`, and `notification_type` (`permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`). SessionStart has `source`; SessionEnd has `reason`; SessionEnd hooks share a 1.5 s budget. `permission_prompt` fires only after the prompt has waited about 6 s, so "needs you" has a built-in delay when using Notification. The signal for "needs you" is finalized in the M2 plan.

### 4.3 Build system
SwiftPM only, with `scripts/bundle.sh` assembling `dist/Shima.app` **[You]**. Logic in `ShimaCore` (tested with `swift test`), thin app in `Shima`, hook CLI `shimactl`.

## 5. Feature evaluation and milestones

### 5.1 Candidate features
| Feature | Verdict | Reason |
|---|---|---|
| Claude session dashboard (sessions, state, elapsed, last message, click to focus) | POC (M2) | Core value |
| Surfacing notifications | POC (M2) | Notification hook carries `message` |
| Approving permissions from the island | **Deferred, not in the POC [You]** | Blocking hook and a security-relevant click target; "I don't need it" |
| Automations config | POC (M4) | Requested |
| Global hotkeys | POC (M4) | Carbon hotkeys need no permission |
| Focus timer, scratchpad, calendar next event | Stretch (M5) | Which ones matter is still open; decided at the M5 review |
| Clipboard history | Drop | Polls `changeCount` (idle cost); macOS 26 pasteboard privacy alerts unclear |
| Volume/brightness HUD replacement | Drop | Needs private hacks |

### 5.2 Milestones (each gets its own plan and review) **[You]**
| M | Scope | Acceptance |
|---|---|---|
| **M0** | Pill, hover expand and collapse, display handling, status menu | See below |
| **M1** | Spotify now playing with artwork, controls, live indicator | **See section 8 (M1 design) for the full scope and acceptance criteria.** Summary: live indicator while playing, open island with artwork, title, artist, controls and a read-only progress bar; event-driven; nothing launches Spotify; artwork from Spotify's CDN; stable signing identity |
| **M2** | Claude sessions | `shimactl` round trip under 50 ms; hook exits 0 in under 600 ms with the app not running. Three concurrent sessions are shown separately (`session_id`) with state, cwd basename, elapsed, last message. "Needs you" changes the island to the attention style. Click activates the terminal app (by bundle id) |
| **M3** | File shelf and AirDrop | Drop 1 to 20 files, **copied** to the shelf by default **[You]** (Option moves). Drag out into Finder, Mail, a terminal. AirDrop opens the system sheet via `NSSharingService(named: .sendViaAirDrop)`. Survives relaunch. Clear empties it. **First task: a spike proving drops and the AirDrop sheet work from a non-activating panel [Unverified]** |
| **M4** | Automations | Edit `config.json`, reload within 1 s (FSEvents). A malformed file keeps the last good config and shows an error badge. Each trigger and action below has a test with a fake event bus |
| **M5 (stretch)** | Chosen from timer, scratchpad, calendar | Decided at the M5 review |

**M0 acceptance criteria.** Each must be checkable by running the app (see the M0 plan for how):

1. **Alignment.** On the built-in notch display, the idle panel frame equals the notch rect within 1 pt. On this Mac that is 179 x 32 pt at the top center **[Verified: auxiliary areas 0–646 and 825–1470 on a 1470 x 956 screen]**. The menu bar is 33 pt tall, so the notch bottom edge sits 1 pt above the menu bar's.
2. **Invisible when idle [You].** With `SHIMA_DEBUG` unset, nothing differs visibly from the bare notch. With `SHIMA_DEBUG=1`, the idle pill is tinted so alignment can be seen.
3. **Hover.** The island starts expanding after the pointer has dwelled on the notch for about 80 ms **[My call on the number; hover trigger is You]**; a pointer passing straight through does not trigger it. It collapses 300 ms after the pointer leaves the expanded area. A click does nothing in M0 **[You: hover only]**.
4. **No flicker.** Wiggling the pointer along the island's edge, or leaving and re-entering during the animation, never produces a flicker or a collapse-expand loop (the expanded hit area is larger than the idle one, so there is hysteresis).
5. **Animation.** Spring expand and collapse growing from the notch with concave top corners, so the island flares into the menu bar like the mockup's "ears" (`mockup/index.html`). Any frame change happens once at the start of expand and after collapse ends, never during the animation.
6. **Focus.** After hover and expand, the frontmost app and key window are unchanged (`NSWorkspace.frontmostApplication` before/after, and typing continues in the previous app). The scaffold's `canBecomeKey = true` and Esc-to-quit are removed.
7. **Menu bar.** Clicking menu bar items outside the island still works, with it idle or expanded. Items directly under the expanded island (about x 353 to 1117 on this Mac) are necessarily covered while it is open, which matches section 2 ("covered only while expanded").
8. **Displays [You].** The panel shows on the built-in display only. If there is no built-in display (clamshell), there is no panel. On a built-in display without a notch (older MacBook), there is no visible pill and an invisible hot zone of 200 x 32 pt at the top center **[Q1: A]**. Plugging or unplugging a monitor, or closing and opening the lid, leaves the panel correct within 1 s.
9. **Spaces and fullscreen [You: always show].** The panel is present on every Space and over a fullscreen app, with no fullscreen detection logic. **[Unverified]**: that `.statusBar` level plus `.fullScreenAuxiliary` is enough; M0 tests it and adjusts the level if not.
10. **Idle cost.** After 60 s with the pointer elsewhere: 0.0% CPU, no timers, no event monitors running (`ps`/`top` and `sample`), RSS under 60 MB.
11. **Status menu.** Quit works. "Launch at login" toggles `SMAppService` and its state matches System Settings **[Unverified]** for an ad-hoc-signed app in `dist/`. If it fails, it moves to a later phase and M0 still passes.

### 5.3 Automations (M4, trimmed [My call])
Config is JSON **[You]**; no third-party parser.

```json
{
  "rules": [
    { "note": "orange pulse when a session needs me",
      "on": "claude.needs_input",
      "do": [ { "pulse": "orange" }, { "sound": "Ping" } ] },
    { "on": "claude.done",
      "when": { "cwd_matches": "kaze-terminal" },
      "do": [ { "expand": "3s" }, { "sound": "Glass" } ] },
    { "on": "hotkey:cmd+shift+n",
      "do": [ { "shell": "~/bin/standup.sh" } ] }
  ]
}
```

| | POC (M4) | Later |
|---|---|---|
| Triggers | `claude.needs_input`, `claude.done`, `claude.started`, `claude.session_end`, `spotify.track_changed`, `hotkey:<combo>` | `shelf.dropped`, click and long-press, `timer.done`, calendar, app activation, gestures |
| Conditions | `cwd_matches` (regex) | `app_frontmost`, `idle_for`, and/or |
| Actions | `expand`, `pulse`, `sound`, `shell` (`/bin/zsh -lc`, event JSON on stdin, 30 s timeout), `spotify` (play/pause/next) | `shortcut`, `http`, `focus_session`, `notify`, `start_timer` |

## 6. Architecture

### 6.1 Layout (as in the repo)
```
Sources/ShimaCore/   logic, testable: NotchGeometry, later AppState, EventBus, SocketServer, Config
Sources/Shima/       thin app: AppDelegate, NotchPanel, ScreenLocator, views
Sources/shimactl/    hook CLI
Tests/ShimaCoreTests Swift Testing
scripts/             bundle.sh, run.sh
```

### 6.2 State
One `@Observable @MainActor AppState`: `mode` (collapsed / expanded), `attention`, later `spotify`, `sessions`, `shelf`. Sessions are pruned on `SessionEnd` or after 2 h without events. M0 needs only `mode`.

### 6.3 Event bus
`AsyncStream<Event>` fan-out; no Combine. Introduced when the second event source arrives (M1/M2), not in M0.

### 6.4 Not stealing focus
`NSPanel` with `[.borderless, .nonactivatingPanel]`, `canBecomeKey` false (true only while a text field is edited, in M5 if at all), `hidesOnDeactivate = false`, level `.statusBar` (to be tuned), collection behavior `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`. Clicks never activate the app.

### 6.5 Geometry and hover **[My call, replaces the earlier design; Unverified until M0 spike]**
The earlier doc toggled `ignoresMouseEvents` by pointer location while also saying no global monitor runs when idle. Those conflict, so:
- Idle: the panel's frame is the notch rect (flush). An `NSTrackingArea` with `.activeAlways` and `mouseEnteredAndExited` on its content view drives hover. No global monitor is needed while idle.
- On dwell, the panel frame grows once (instantly, to the expanded size, transparent) and the SwiftUI content animates inside it. After the collapse animation ends, the frame shrinks back. The menu bar is only covered while expanded.
- While expanded, hover is judged against the expanded shape plus a margin (hysteresis). Collapse is a 300 ms debounce.
- The notch rect is the screen frame minus `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`, `safeAreaInsets.top` tall **[Verified on this Mac]**, with the virtual-notch fallback (200 x 32) when absent. Recomputed on `didChangeScreenParametersNotification`. The formula is not documented by Apple, so it is measured on one machine only.
- If the one-time frame change causes visible flicker, the fallback is **two panels [My call, from the M0 plan]**: an always-expanded-size visual panel, plus a notch-sized invisible "sensor" panel that carries the idle tracking area. A single fixed expanded panel toggling `ignoresMouseEvents` would get no tracking events while idle and would need a global monitor, which breaks the idle rule. M0 spikes the first approach first.
- **Invisible but hoverable [Unverified]:** the no-notch hot zone and the 8 pt hover margin around the expanded island must receive hover while drawing nothing. Fully transparent pixels may pass events through, so the M0 spike measures the smallest invisible alpha (expected 0 or 0.01) that still receives events.

### 6.6 Animation
One SwiftUI shape with animatable width, height and corner radii, using a spring (starting point `response 0.35, dampingFraction 0.8`). `UnevenRoundedRectangle` cannot draw concave corners, so M0 uses a custom `Shape` with animatable data. Content cross-fades. Any pulse runs only while `attention != none`.

### 6.7 Idle
No timers while collapsed. SwiftUI animations run only while animating. Elapsed-time labels use `TimelineView` only while expanded. Artwork cached by URL.

## 7. Decisions and open items

**Decided by you (2026-11-21)**
| # | Question | Answer |
|---|---|---|
| 1 | Non-notch displays | Invisible hot zone, no visible pill (A) |
| 2 | Which display | Built-in only. No panel on external monitors, and none when there is no built-in display |
| 3 | Fullscreen | Always show |
| 4 | Expand trigger | Hover only |
| 5 | Signing | Self-signed certificate, set up in M1 |
| 6 | Config format | JSON; trimmed automations |
| 7 | Shelf | Copy by default |
| 8 | Permission approvals | Deferred, not wanted |
| 9 | Spotify artwork | Allowed, and shown |

**Still open (not needed before their phase)**
- Which M5 stretch items matter (timer, scratchpad, calendar).
- Which hook signal marks "needs you" in M2 (Notification `permission_prompt` has a ~6 s delay; the alternative is observing the `PermissionRequest` event without deciding anything, which I would only do if you agree).
- Whether the status menu also needs "Reload config" (M4).

**Risks / unverified**
- Frame-grow-at-expand may flicker (M0 spike); fullscreen behavior at `.statusBar` level (M0).
- `SMAppService` with ad-hoc signing (M0).
- Drag and drop and the AirDrop sheet from a non-activating panel (M3 spike).
- Spotify's distributed notification is undocumented and could change (M1).
- macOS 26 pasteboard privacy (only if clipboard history is revived).

## 8. M1 design: Spotify (2026-11-21)

Written after the M0 build and revised after an independent review (an Opus pass over the author's calls, 2026-11-21). Tags: **[You]** = decided by the user, **[My call]** = the author's, **[Review]** = changed or added by the independent review, **[Verified]**, **[Unverified]**. M1 gets its own plan and review; this section is the spec that plan argues from.

### 8.1 Decisions
| # | Question | Answer |
|---|---|---|
| 1 | Does the collapsed island do anything while music plays? | **Yes: a small live indicator [You]** |
| 2 | How does the indicator move? | **Animated equalizer, continuously [You].** Explicit exception to the 0.0% idle-CPU rule, only while Spotify is playing |
| 3 | What does the open island show? | **Artwork, title, artist, play/pause, next, previous, plus a read-only progress bar with elapsed and remaining time [You]** |
| 4 | Peek when the track changes? | **No peek in M1 [You].** It returns in M4 as an automation action |
| 5 | How do we get Spotify state? | **Event-driven [You]**: system launch/quit notifications plus Spotify's playback-changed broadcast; no polling |
| 6 | Artwork from Spotify's CDN | Allowed [You] |
| 7 | Wing width and sides | **33 pt wings, mini artwork on the left, equalizer on the right [You, accepting the review's pick].** The mockup's 58 pt wings would cover the first status item |
| 8 | Paused Spotify | **Show nothing [You].** The indicator exists only while playing |
| 9 | Signing | **Use an existing Apple Development identity, no new keychain entry [You: "existing one"].** Which one: **#1 `Apple Development: jpatrickzephyr@gmail.com (<cert-id>)` [My call: the personal one; #2 looks like a work account]** |
| 10 | Test playback | **A muted Spotify Private Session on the user's account is fine for hands-on checks [You]** |

### 8.2 Behavior
- **Spotify not running:** nothing is drawn while idle. The open island shows "Spotify is not running". No Apple Event is ever sent and Spotify is never launched (see 8.4).
- **Playing, island collapsed (live state):** the collapsed island widens beyond the notch by **33 pt on each side** (live width = notch + 66; on this Mac 245 pt, frame x 613 to 858, y 0 to 32) **[Review]**. No wing may overlap the first menu bar status item, which starts at x 860 here; the gap from the notch to that item is 35 pt **[Verified, M0 acceptance]**. Left wing: 20x20 mini artwork (rounded 5). Right wing: 4 equalizer bars (2.5 pt wide, about 16 pt in all, 14 pt tall) in Spotify green `#1ED760`, white if green looks loud **[My call]**. Both vertically centred in the 32 pt strip; collapsed ear radius stays 0. The mockup puts artwork and bars both on the left and keeps the right wing for Claude session dots; M2 will rearrange the wings when it lands.
- **Paused, stopped, no track, or Spotify quit:** no indicator, the island is invisible at idle as in M0 **[You]**.
- **Open island** (hover as in M0), proposed layout inside 360x165 (content area below the 32 pt notch strip is 133 pt) **[Review, arithmetic only]**: artwork 88x88 at x 14, y 44 to 132; right column x 116 to 346: title 15 pt semibold, artist 12.5 pt, progress bar 4 pt with elapsed/remaining times in 11 pt monospaced digits, then the controls row (previous and next 28 pt, play/pause 32 pt). No growth of the island is expected; if it looks cramped when first seen, the height grows and the user decides.
- **Progress bar:** the position is read when the island opens and on each Spotify notification, then extrapolated by a pure function `position(at:)` clamped to the track duration. A `TimelineView(.periodic(by: 1))` runs only while the island is open and playing; paused shows a static value with no timeline. Whether a seek inside Spotify posts a notification is unverified; if not, the value re-syncs on open **[Review]**.
- **Clicks:** the three buttons work; everything else still ignores clicks. Buttons sit only on opaque island pixels (transparent pixels pass clicks through, Spike 1). A click never activates Shima or Spotify: the panel stays non-key, the hosting view returns `acceptsFirstMouse` true, no key focus, the arrow cursor stays **[Review]**.
- **Ads on the free tier** appear as ordinary tracks. A missing or empty artwork URL shows the placeholder **[My call]**.
- **Artwork:** ephemeral `URLSession` (no disk cache), `NSCache` with `countLimit` about 10, downsampled to 176 px; the in-flight fetch is cancelled on a track change and stale results are dropped; failure shows the placeholder and retries only on the next track. This is the only network access **[Review]**.
- **Permission:** the first Apple Event triggers the macOS Automation prompt for Spotify (`NSAppleEventsUsageDescription` in Info.plist). Denial is detected from error **-1743** on a real event and the open island shows an instruction (System Settings, Privacy & Security, Automation). Retry only on the next Spotify notification or the next island open, never on a timer, so a grant made later is noticed. Launch the app only through `open` (as `scripts/run.sh` does) so the prompt is attributed to Shima and not to the terminal **[Review]**.

### 8.3 Acceptance criteria (each checkable by running the app)
1. Track, artist and artwork update within 1 s of a change in Spotify.
2. Play/pause, next and previous work from the island, and the island follows changes made in Spotify itself.
3. With Spotify quit: no indicator, "Spotify is not running" when open, and Shima never launches Spotify (`pgrep -x Spotify` stays empty).
4. The live indicator appears when playback starts and disappears when Spotify pauses, stops or quits.
5. The progress bar ticks only while the island is open and playing (no timer while collapsed).
6. M0 behaviors still hold in the live state: dwell, collapse, no flicker, focus never stolen **with real button clicks** (`scripts/verify-focus.sh` extended, `NSApp.isActive` stays false), menu bar clicks outside the island still work, **and menu bar items at x 860 and right stay clickable while live**. The live frame matches the layout values within 1 pt (`scripts/verify-alignment.sh` gets a live mode) **[Review]**.
7. **CPU [Review]:** with Spotify not playing, `scripts/verify-idle.sh` stays strict at 0.0%. With Spotify playing and the island collapsed, **Shima's own CPU stays at or below 0.1% on average and the WindowServer increase stays at or below about 1.5%**, measured as an A/B of bars animating versus frozen (the fake-Spotify flag below makes this repeatable). Numbers are reported honestly even if worse. `verify-idle.sh`'s static check also flags `repeatCount` and similar, with a file allowlist for the equalizer layer.
8. The Automation permission survives a rebuild (stable signing identity).

### 8.4 Architecture
- **ShimaCore (pure, tested):**
  - `NowPlaying` (title, artist, album, artworkURL, duration, position, state), `PlaybackState`, `SpotifyEvent`.
  - `SpotifyModel.apply(SpotifyEvent) -> (NowPlaying?, [SpotifyChange])` where `SpotifyChange` includes `.trackChanged(id)` and `.stateChanged`. One `@MainActor` coordinator applies results to `AppState.spotify`. M2 forwards `SpotifyChange` to the event bus unchanged, and M4's `spotify.track_changed` trigger is that change. No bus now **[My call, seam from Review]**.
  - A `SpotifyClient` protocol with a fake for tests; `position(at:)`.
  - `IslandLayout`: the idle frame and idle hot rect become functions of `(notch, live)`.
  - **HoverMachine gains one input, `.idleGeometryChanged`.** It emits `[.shrinkPanel]` (re-apply the idle frame) only when the panel is small; when the panel is large (expanded, or dwelling after a re-entry during a collapse) it returns `[]` and the next `shrinkPanel` after the collapse picks up the new idle frame. The collapsed shape's live flag changes only while the panel is small, so no metrics change retargets an in-flight collapse. Live start animates the wings in after an instant frame grow; stop snaps. `reset()` re-applies the idle frame with the current live flag. Tests cover the input in all five phases and the large-`dwelling` case **[Review]**.
- **Shima (glue):**
  - **Scripting [Review, replaces the earlier plan]:** `SpotifyScripting` is a `final class` marked `@unchecked Sendable` with its own private serial `DispatchQueue`. It sends raw Apple Events with `NSAppleEventDescriptor(processIdentifier:)` and `sendEvent(options: .waitForReply, timeout: 2s)`. **No `NSAppleScript` and no `tell application`**: compiling AppleScript on a background thread can deadlock on macOS 26.2+ (XProtect's one-time setup must run on the main thread, FB21334477), and `tell application "Spotify"` launches Spotify if it quit a moment ago. The target pid comes from `NSRunningApplication(bundleIdentifier: "com.spotify.client")`; an event to a dead pid returns -600 and launches nothing (tested by the reviewer). Event codes from the sdef: `pPlS` player state, `pPos` position, `pTrk` current track; track `pnam`, `pArt`, `pAlb`, `pDur`, `aUrl`, `'ID  '`; commands `spfyPlPs`, `spfyNext`, `spfyPrev`.
  - Requests are coalesced (one in flight plus a dirty flag), tagged with a sequence number and pid; stale results are dropped on the main actor; `didTerminate` clears state; errors -600 and -609 mean "not running"; -1712 is a timeout.
  - The playback notification observer uses `suspensionBehavior: .deliverImmediately`, and parses `userInfo` into a `Sendable` struct in the callback. If the payload already carries name, artist, state and position, it is used directly and scripting is only for `artwork url` and the controls. **No Apple Events on `didLaunchApplication`**; one snapshot at Shima start only if Spotify is already running.
  - **Equalizer:** Core Animation layer animations in an `NSViewRepresentable`, not SwiftUI's repeating animation. Measured by the reviewer on this Mac (4 bars): Shima at 0.00% with Core Animation versus 2.45% with `repeatForever`, at the cost of about 1% more in WindowServer. Rules: add animations idempotently in `viewDidMoveToWindow`/`updateNSView`, keep the view identity stable, `isRemovedOnCompletion = false`, wrap changes in `CATransaction.setDisableActions(true)`, pause by removing the animations and setting the rest transform (measure that a frozen layer costs nothing), and re-add them after `orderOut`/`orderFront`.
  - `ArtworkCache` as in 8.2; SwiftUI views for the wings and the open island.
  - **Fake mode:** `SHIMA_FAKE_SPOTIFY=playing|paused` drives the real UI without Spotify, so the CGEvent hover scripts, the alignment live mode and the CPU A/B run without music.
- **Signing [Review]:** `scripts/bundle.sh` takes `SHIMA_SIGN_ID` and falls back to ad-hoc; hardened runtime stays off, so no `apple-events` entitlement is needed; `NSAppleEventsUsageDescription` goes in Info.plist; the first signing shows a "codesign wants to access key" prompt; the identity expires yearly and Automation must then be re-granted; the app is unsandboxed, so no network entitlement. The ad-hoc requirement is `cdhash`-based and changes with every rebuild, so the grant would not survive without this.

### 8.5 Verified and unverified
- **[Verified]** Spotify 1.3.10 is installed on the dev Mac; its sdef (read without launching it) exposes current track name, artist, album, duration, artwork url, id, player state, player position (read/write), and play, pause, playpause, next track, previous track. There is **no queue**, so the mockup's "next three tracks" is out.
- **[Verified by the reviewer]** Core Animation versus SwiftUI CPU numbers above; an Apple Event to a dead pid returns -600 and launches nothing; the login keychain has two valid Apple Development identities.
- **[Unverified, first-spike items in the M1 plan]:** the payload and rate of `com.spotify.client.PlaybackStateChanged`; whether seeks post it; `acceptsFirstMouse` and button behavior in the non-key panel; the Automation prompt and persistence with the chosen identity; whether a frozen Core Animation layer costs nothing; the artwork URL form; and **a live-frame change during hover**. The live-frame spike toggles live while the pointer is on the notch, while dwelling, mid-expand, and mid-collapse with a re-entry, and checks the log for exactly one frame change per transition and no `collapsing` loops. Last-resort fallback if it flickers: a constant-width idle frame (notch plus wings, transparent when not live) with only the hot rect changing, which would break M0 criterion 1 and depends on click-through over menu items.

### 8.6 Verification
Automated: reducer and fake-client tests, layout tests (live frame, hot rects), `.idleGeometryChanged` tests, and fake-mode scripts for hover, alignment and the CPU A/B. Needs the user: the Automation prompt, the payload spike, the controls, and criterion 1, using a muted Private Session.

### 8.7 Out of scope for M1
Peek (M4), seeking, volume, a queue, colour extraction from artwork, Apple Music, any account or Web API use, a menu reachable from the island (the status icon is still hidden on a full menu bar), and Launch at login (retry later with the app in `/Applications`, which needs the user's OK).

### 8.8 Left to the builder
Exact view layout and animation curves, the shape of the fake client, file organization within 6.1, and how the live-frame change is made flicker-free within the machine described above.
