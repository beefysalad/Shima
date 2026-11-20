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
| CPU use while idle | No timers or polling when collapsed; event-driven only. Target 0.0% CPU idle |
| Accounts or API keys | None. The only network request is Spotify artwork from its CDN **[You]** |
| Flicker or jitter at the notch | One persistent panel; animate content, never recreate windows |
| Stealing focus from the active app | Non-activating panel; see 6.4 |
| Slowing Claude Code down | `shimactl` always exits 0 within 1 s, even when the app is not running |
| Blocking clicks on the menu bar | The panel only covers the notch strip while idle; it grows only while expanded |

## 3. Constraints

| Item | Decision |
|---|---|
| OS | macOS 26 on Apple Silicon (dev machine); deployment target 14.0 (for `UnevenRoundedRectangle`, `@Observable`) |
| Toolchain | **Swift 6.1 and SwiftPM only; Command Line Tools, no Xcode, no `.xcodeproj`** **[You]**. Everything builds with `swift build` |
| Dependencies | None third-party without asking **[You]** |
| UI | SwiftUI views in one borderless non-activating `NSPanel` **[You]** |
| Sandbox | Off **[My call]**: Unix socket, `~/.claude` reads, shell actions and Apple Events to Spotify are awkward inside the sandbox, and a personal app gains nothing from it |
| Hardened runtime | **Not enabled for now [My call]**. The current `bundle.sh` does not enable it. It only matters if we turn it on, which needs the `apple-events` entitlement in M1. Revisit in M1 |
| Signing | M0: ad-hoc (`codesign -s -`), as scaffolded. **M1: a self-signed certificate in the login keychain for a stable identity [You, "go with recommended"]**, so Spotify automation permission survives rebuilds. It is free and needs no Apple account. It writes to the keychain outside the repo, so I will ask again before doing it |
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
| **M1** | Spotify now playing with artwork, controls | Track, artist, artwork update within 1 s of a change. Play/pause, next, previous work. With Spotify quit, the module hides and nothing launches Spotify. Artwork is fetched from Spotify's CDN and cached by URL **[You]**. Stable signing identity set up |
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
7. **Menu bar.** Clicking menu bar items on either side of the notch still works, with the island idle or expanded.
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
- If the one-time frame change causes visible flicker, the fallback is a fixed expanded-size panel with `ignoresMouseEvents` toggled; M0 spikes the first approach first.

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
