# Notch: scope and design (POC)

2026-11-20. Status: draft for review. Where this doc says "recommended", that is a recommendation. The user has not chosen yet.

## 1. Intent

A personal, free "Dynamic Island" for the MacBook notch, replacing a NotchBox subscription. It is built for one person's day: Claude Code sessions running in kaze or any other terminal, Spotify playing, and files moving around. The notch is dead space that is always visible. Making it the place that answers "does any Claude session need me?" and "what's playing?" without a window switch is the whole point. It is a POC: small, local, and hackable, not a product.

## 2. Goals, non-goals, anti-goals

**Goals**
- A pill around the notch that expands on hover and collapses without fuss. It must feel native on notch, non-notch and multi-monitor setups.
- Glanceable Claude Code state for each session (running / needs you / done), and one click jumps to that terminal.
- Spotify now playing with controls.
- A file shelf: drop files on the notch, drag them back out, AirDrop them.
- Automations from one human-editable config file.

**Non-goals (POC):** system-wide Now Playing (MediaRemote is restricted), Apple Music, camera mirror, widgets, themes, distribution or notarization, other users, Windows or Linux.

**Anti-goals (must never happen)**
| Anti-goal | Guard |
|---|---|
| CPU use while idle | No timers or polling when collapsed; event-driven only. Target ~0.0% CPU when idle (see 6.7) |
| Accounts, API keys, network | No network entitlement is needed; everything goes over local IPC |
| Flicker or jitter over the notch | One persistent panel; animate content, never recreate windows |
| Stealing focus from the active app | Non-activating panel; see 6.4 |
| Slowing Claude Code down | The hook helper always exits 0 within 1 second, even when the app is not running |
| Blocking clicks on the menu bar | The panel ignores mouse events outside the pill's shape |

## 3. Constraints

| Item | Decision |
|---|---|
| OS | macOS 26 (Darwin 25.6), Apple Silicon. Deployment target 14.0 (needed for EventKit `requestFullAccessToEvents` if calendar ships; otherwise 13.0) |
| Toolchain | Swift 6 and Xcode, installed locally. No App Store |
| Sandbox | **Off (my call).** The Unix socket in `~/Library/Application Support`, reading `~/.claude`, running user shell scripts, and sending Apple Events to Spotify are all awkward or impossible inside the sandbox. NotchBox is sandboxed and needs temporary-exception entitlements for Spotify. A personal app gains nothing from the sandbox. Hardened runtime stays on, with the `com.apple.security.automation.apple-events` entitlement |
| Automation (TCC) | Once, for Spotify (`NSAppleEventsUsageDescription`). Later also System Events and Terminal/iTerm if window focusing uses AppleScript |
| Accessibility | **Not needed in the POC.** Carbon `RegisterEventHotKey` hotkeys and the global mouse-move monitor do not need it. Raising one specific window of another app would need it (later) |
| Calendar | Full Access to Events, only if M5 calendar ships |
| Files | Shelf files live in `~/Library/Application Support/Notch/Shelf/`. No user-selected scoped access is needed because the app is unsandboxed |
| Autostart | `SMAppService.mainApp.register()` (macOS 13+), toggled from the menu |
| Background | `LSUIElement = YES`, so no Dock icon. A small status-bar menu offers Quit, Reload config and Launch at login |
| Signing | Local "Sign to Run Locally" or the user's personal team. TCC grants survive rebuilds only while the signing identity stays stable, so use one fixed identity |

## 4. Approaches

### 4.1 UI stack
| Option | Pros | Cons |
|---|---|---|
| **A. SwiftUI views in one AppKit `NSPanel` (recommended)** | Fast to iterate, spring animations are free, AppKit keeps control of window level, focus and hit-testing | Some SwiftUI layout quirks during resize animation; needs care with `NSHostingView` sizing |
| B. AppKit-heavy (CALayer and NSView) | Tightest control over frame-perfect animation and CPU | Two to three times the code; slower to build features |
| C. Pure SwiftUI `Window`/`MenuBarExtra` scenes | Least code | Cannot reliably get a non-activating, menu-bar-level, borderless panel; rejected |

### 4.2 Claude Code event transport
| Option | Pros | Cons |
|---|---|---|
| **A. Unix domain socket (recommended)** | Instant; no port or token needed (file permissions 0600 protect it); trivially "down" when the app is not running | Needs a tiny client: a bundled helper, or `nc -U` |
| B. File drop plus FSEvents watch | Zero client code (`cat >> file`); survives app restarts | Latency and coalescing; file cleanup; harder to get exact ordering |
| C. Local HTTP on loopback | Debuggable with curl | A port in use, an auth token (kaze needed one), an open listener; more surface than needed |

Recommended client: a ~100-line Swift CLI `notchctl` bundled at `Notch.app/Contents/MacOS/notchctl`. A hook runs `notchctl hook <event>`. It reads the hook JSON from stdin, adds `ppid`, `tty`, `TERM_PROGRAM` and `__CFBundleIdentifier` from its own environment (these are what make "focus the terminal" possible), and writes one JSON line to `~/Library/Application Support/Notch/notch.sock`. It has a 500 ms timeout and always exits 0. These hooks are added **next to** the existing `kaze notify` hooks in `~/.claude/settings.json` (kaze uses its own loopback TCP listener; the two do not interact).

### 4.3 Build system
| Option | Pros | Cons |
|---|---|---|
| SwiftPM only | Plain text, `swift build`, friendly to Claude Code | No .app bundle, Info.plist or entitlements without a packaging script |
| **SwiftPM package for logic, plus a thin Xcode app target (recommended)** | Tests run with `swift test`; Xcode handles the bundle, signing and entitlements; `xcodebuild` works from the CLI | Two files to keep in sync |
| Xcode project only | Simplest bundle setup | The `.pbxproj` churns and is harder for an AI agent to edit |

A Tuist or XcodeGen `project.yml` is a reasonable alternative to a hand-kept `.xcodeproj`, if the user wants that.

## 5. Feature evaluation and milestones

### 5.1 Candidate features
| Feature | Verdict | Reason |
|---|---|---|
| Claude session dashboard (several sessions, state, elapsed time, last message, click to focus) | **POC (M2)** | The core value for an AI-dev workflow |
| Surfacing notifications | **POC (M2)** | The Notification hook carries a `message` string; show it |
| Approving permissions from the notch (PermissionRequest hook returns allow/deny) | Later, user decision | Feasible, but a blocking hook and a security-relevant click target |
| Automations config | **POC (M4)** | Explicitly requested |
| Global hotkeys | **POC (M4)** | Carbon hotkeys need no permission; they are the automation triggers |
| Focus timer (pomodoro) | Stretch (M5) | Cheap, fits the notch well, and works as an automation trigger |
| Quick scratchpad | Stretch (M5) | One text file, a tiny view; useful for "note to self while Claude works" |
| Calendar next event | Stretch (M5) | EventKit is local and cheap, but needs a TCC prompt |
| Clipboard history | Later / drop | Needs polling of `changeCount` (the one idle cost), and macOS 26 pasteboard privacy alerts may apply (see 7). Tahoe's Spotlight already has clipboard history |
| Volume/brightness HUD replacement | Drop | Hiding the system HUD needs private hacks; fragile |
| Kaze integration | Not needed | Kaze sessions arrive through the same Claude hooks |

### 5.2 Milestones and acceptance criteria
| M | Scope | Acceptance (verifiable) |
|---|---|---|
| **M0** | Notch pill, hover expand/collapse, screen handling, status menu, launch at login | Pill aligns with the camera housing within 1 pt on the built-in display. On a display without a notch, it shows a 200x32 pt pill at top center. Hover expands within 150 ms, and collapse happens 300 ms after the pointer leaves. Clicking the menu bar beside the pill reaches the menu bar. The frontmost app keeps key focus after hover and click (check with `NSWorkspace.frontmostApplication`). Plugging or unplugging a monitor moves the panel within 1 s. The panel shows on every Space and over fullscreen apps (configurable). Idle CPU in Activity Monitor is 0.0% over 60 s |
| **M1** | Spotify | Track, artist and artwork update within 1 s of a change. Play/pause, next and previous work. With Spotify quit, the module hides and no Apple Event launches Spotify (check `NSRunningApplication` first) |
| **M2** | Claude sessions | `notchctl` round trip under 50 ms. With the app not running, a hook exits 0 in under 600 ms. Three concurrent sessions show separately (keyed by `session_id`) with state, cwd basename, elapsed time and last message. "Needs you" moves the collapsed pill to the attention style. Clicking a session activates its terminal app (kaze, Terminal, iTerm, Ghostty and others, by bundle id) |
| **M3** | File shelf and AirDrop | Dropping 1 to 20 files on the pill copies them to the shelf (copy is the default; holding Option moves them). Dragging out works into Finder, Mail and a terminal. AirDrop opens the system sheet via `NSSharingService(named: .sendViaAirDrop)`. Shelf contents survive a relaunch. "Clear" empties it |
| **M4** | Automations | Editing `config.toml` reloads within 1 s (FSEvents). A malformed file keeps the last good config and shows an error badge. Each POC trigger and action in 5.3 has a test with a fake event bus |
| **M5 (stretch)** | Focus timer, scratchpad, calendar next event, PermissionRequest approvals | Each is its own toggle in the config; off by default except the timer |

### 5.3 Automations
Configuration lives in one file, `~/.config/notch/config.toml` (TOML: readable, comments allowed; parse it with a small vendored parser or TOMLKit). Example:

```toml
[[rule]]
on = "claude.needs_input"
do = [{ pulse = "orange" }, { sound = "Ping" }]

[[rule]]
on = "claude.done"
when = { cwd_matches = "kaze-terminal" }
do = [{ expand = "3s" }, { sound = "Glass" }]

[[rule]]
on = "hotkey:cmd+shift+n"
do = [{ shell = "~/bin/standup.sh" }]

[[rule]]
on = "gesture.swipe_down"
do = [{ shortcut = "Start Focus" }]
```

| | POC (M4) | Later |
|---|---|---|
| Triggers | `claude.needs_input`, `claude.done`, `claude.started`, `claude.session_end`, `spotify.track_changed`, `hotkey:<combo>`, `notch.click`, `notch.long_press`, `shelf.dropped` | `timer.done`, `calendar.starts_in:<min>`, `app.activated:<bundle id>`, schedules, swipe gestures |
| Conditions | `cwd_matches` (regex), `app_frontmost`, `idle_for` | Combining conditions with and/or |
| Actions | `expand`, `pulse`, `sound` (system sound name or file), `shell` (runs `/bin/zsh -lc` with event JSON on stdin; 30 s timeout), `shortcut` (`/usr/bin/shortcuts run`), `spotify` (play/pause/next) | `focus_session`, `notify` (UNUserNotification), `start_timer`, `http` to localhost |

## 6. Architecture

### 6.1 Layout
```
Notch/            Xcode app target: AppDelegate, Info.plist, entitlements
NotchCore/        SwiftPM library (all logic, testable)
  Panel/          NotchPanel (NSPanel), ScreenLocator, HoverTracker
  UI/             RootView, CollapsedView, ExpandedView, modules/*
  Bus/            EventBus, Event enum
  Modules/        Spotify/, Claude/, Shelf/, Timer/, Scratch/
  Automations/    ConfigLoader, RuleEngine, Actions/
  IPC/            SocketServer (DispatchSource on a Unix socket)
notchctl/         SwiftPM executable (hook client)
```

### 6.2 State
One `@Observable @MainActor AppState`: `mode` (collapsed / peek / expanded), `attention` (none / pulse(color)), `spotify: NowPlaying?`, `sessions: [SessionID: ClaudeSession]` (`state`, `cwd`, `startedAt`, `lastMessage`, `terminalBundleID`, `ppid`, `tty`), `shelf: [URL]`. Sessions are pruned on `SessionEnd`, or after 2 h with no events.

### 6.3 Event bus
An `AsyncStream<Event>` fan-out. Sources (socket, Spotify notification, hotkeys, FSEvents, hover) publish to it; modules and the RuleEngine subscribe. Actions are plain async functions. There is no Combine.

### 6.4 Not stealing focus
An `NSPanel` with style mask `[.borderless, .nonactivatingPanel]`, `canBecomeKey` overridden to false (true only while the scratchpad text field is being edited), `hidesOnDeactivate = false`, level `.statusBar` (or `mainMenu + 1`), and collection behavior `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`. Clicks never activate the app. Drag and drop and the AirDrop sheet work without the app becoming active (to verify in M0/M3).

### 6.5 Geometry and hit-testing
The notch rect is the screen frame minus `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`; its height is `safeAreaInsets.top`. If those are nil or zero, use a "virtual notch" (200x32 pt, top center). Recompute on `NSApplication.didChangeScreenParametersNotification`. The panel is sized to the largest expanded state and transparent elsewhere. A `hitTest` override returns nil outside the current pill shape, and `ignoresMouseEvents` toggles by pointer location, so the menu bar stays usable. For hover, an `NSTrackingArea` on the pill, plus a global `mouseMoved` monitor only while expanded (it does not run while idle). Multi-monitor: default to the built-in screen; config `screen = "builtin" | "main" | "pointer"`.

### 6.6 Animation
The pill is one SwiftUI shape with animatable width, height and corner radius, using `.spring(response: 0.35, dampingFraction: 0.8)`. The window frame never changes during animation (this is what prevents flicker). Content cross-fades with `matchedGeometryEffect`. The pulse is a repeating opacity/scale animation that runs only while `attention != none`.

### 6.7 Fullscreen and idle
In fullscreen apps on the built-in display the notch area is black; the pill still draws via `.fullScreenAuxiliary`. A config flag `hide_in_fullscreen` detects fullscreen by checking whether the menu bar is hidden for the frontmost window's screen; the exact method is to be confirmed in M0. Idle budget: no timers while collapsed; elapsed-time labels use `TimelineView(.periodic(by: 1))` only while expanded; artwork is cached by URL. Target: 0.0% CPU when idle and under 60 MB RSS.

## 7. Risks and open questions

**Answered / my call**
- Sandbox off; hardened runtime on (reasons in 3).
- Unix socket plus a bundled `notchctl`; the existing kaze hooks stay untouched.
- TOML config at `~/.config/notch/config.toml`.
- Clipboard history and the HUD replacement are out of the POC.
- "Click to focus" in the POC only activates the right terminal app. Raising the exact tab or window is later (AppleScript for Terminal/iTerm by tty; for kaze, a possible future `kaze focus <session>` command).
- Spotify artwork comes from AppleScript `artwork url of current track` (an HTTPS image URL). Fetching it is the only network access, and it goes to Spotify's CDN (`URLSession`, no key). If even that is unwanted, show a placeholder.

**Risks / unverified**
- macOS 26 pasteboard privacy: `NSPasteboard.accessBehavior` exists, but sources disagree on whether the alert is on by default in 26. This matters only if clipboard history is revived.
- Notch-width math (frame minus the auxiliary areas) is inferred, not documented by Apple. One report says `safeAreaInsets` returned zeros on a notch Mac. Measure in M0.
- The exact Claude Code hook payload fields (`notification_type`, `PermissionRequest` schema) come from third-party references. Confirm against code.claude.com/docs/en/hooks during M2.
- That drag and drop and the AirDrop sheet work from a non-activating panel is assumed and needs testing.
- Spotify's distributed notification is undocumented and could change.

**Needs the user's decision**
1. Approve the recommended stack (SwiftUI-in-NSPanel, Unix socket, SwiftPM plus a thin Xcode target)?
2. Should approving Claude permission requests from the notch (PermissionRequest hook) be in scope at all, and if so, in M5 or later?
3. Which stretch items matter: focus timer, scratchpad, calendar next event?
4. Should the shelf copy (safe) or move (no duplicates) files by default?
5. Behavior in fullscreen apps: always show, or hide?
6. Which display gets the panel on multi-monitor setups by default: built-in, main, or the one with the pointer?
7. Is the Spotify CDN artwork fetch acceptable under the "everything local" rule?
8. App and bundle name (placeholder: "Notch", `local.notch`).
