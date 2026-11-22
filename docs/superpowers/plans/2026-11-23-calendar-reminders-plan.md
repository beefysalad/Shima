# Calendar and Reminders tab Implementation Plan

> **For agentic workers (Codex):** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax. Read `CLAUDE.md` first: it holds the project rules and gotchas. Work in a worktree `.worktrees/calendar` on branch `calendar` (`git worktree add .worktrees/calendar -b calendar`). Task labels: **PURE** (ShimaCore, tests, no AppKit/EventKit), **GLUE** (Shima app), **SCRIPT**, **HUMAN/CLAUDE** (not for Codex; skip and report when you reach one).

**Goal:** A Calendar tab in the open island showing the selected day's events and due reminders and a month grid, from the macOS Calendar and Reminders stores.

**Architecture:** Same shape as Camera. Pure `CalendarModel` reducer + `CalendarCoordinator` + `CalendarClient` protocol (with a fake) in `ShimaCore`; an EventKit client, a service and a SwiftUI overlay in `Shima`. Refresh is event-driven (`EKEventStoreChanged`, `NSCalendarDayChanged`), only while the tab is visible.

**Tech Stack:** Swift 6 toolchain, SwiftPM only, Swift Testing (`import Testing`, no XCTest), EventKit, SwiftUI in the existing `NSPanel`. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-11-23-calendar-reminders-design.md`. Mirror these existing files when in doubt: `Sources/ShimaCore/{CameraModel,CameraClient,FakeCameraClient,CameraCoordinator}.swift`, `Sources/Shima/{CameraService,CameraContent}.swift`, `Tests/ShimaCoreTests/CameraTests.swift`, `scripts/verify-camera.sh`.

## Global Constraints

- `ShimaCore` must not import AppKit or EventKit. All EventKit code lives in `Sources/Shima/`.
- SwiftPM only, no `.xcodeproj`; no third-party dependencies.
- No polling, no repeating timers, no work while the Calendar tab is not visible; no permission prompt at launch or on hover; prompts only on first opening the Calendar tab (Calendar first, then Reminders).
- Nothing may enlarge the island root `ZStack` (hidden views still take part in layout): the Calendar panel is an overlay with explicit frames, like `CameraContent`. Island stays 400 x 200.
- The real UI must match the approved `mockup/index.html` (Task 0 updates it first).
- Commit messages: plain, no attribution trailers (a hook rejects them). Stage explicit paths, never `git add -A`. Never commit signing identifiers or `.build`/`dist`. Do not touch `~/.claude/settings.json` or any file outside the repo.
- `shimactl` and Spotify code are out of scope; do not modify them. Never launch or command the user's Spotify.
- `scripts/bundle.sh` Info.plist keys to add: `NSCalendarsFullAccessUsageDescription`, `NSRemindersFullAccessUsageDescription`.
- The terminal has no Screen Recording permission: verify with logs, window list, CGEvent input and offscreen `cacheDisplay` renders.

## Review Focus

Failure modes the spec implies that no feature test would otherwise exercise (each is pinned by a named test below):

1. An all-day event ends at the next day's 00:00 (exclusive); it must not appear on, or dot, the next day (Task 2: `allDayEventEndExclusive`).
2. Monday-first locales: weekday header and grid rows follow `calendar.firstWeekday` (Task 2: `mondayFirstGrid`).
3. A slow load finishing after a newer one, or after the tab closed, must not overwrite newer data (Task 3: `staleLoadCompletionIsDropped`).
4. Access revoked in System Settings while shima runs: on the next refresh the tab shows the denied state and drops cached data (Task 3: `revokedAccessClearsData`).
5. Events with an empty title show "(No title)"; a day with 6 weeks of grid still fits (Task 2: `emptyTitleFallback`, Task 5: six-week offscreen render).

---

### Task 0: Mockup and layout table (HUMAN/CLAUDE, not Codex)

Claude updates `mockup/index.html` (Calendar tab matching the DynaGlance reference and the spec; Calendar icon added to the header strip; denied state; six-week month) and the user approves it. Output also appended to the spec as a "Layout table": every rect and font size used by Task 4 (`CalendarLayout` values) and the final header icon positions.

**Known constraint Codex must respect:** the notch hides x 110.5..289.5 of the island's header. Today's header icons sit at x 14 (Home), 42 (Music), 70 (Camera), each 24 wide; a fourth at x 98 would overlap the notch. Task 0 decides the fix (planned: 22 pt hit areas on a 24 pt pitch starting at x 12, so the fourth icon spans 84..106). Codex reads the final numbers from the spec's Layout table; if the table is missing, stop and report.

- [ ] Codex: do not start Task 4 until the spec's Layout table exists and the user's approval is recorded in it.

### Task 1: Types and the Calendar tab case (PURE)

**Files:**
- Create: `Sources/ShimaCore/CalendarTypes.swift`
- Modify: `Sources/ShimaCore/CameraModel.swift:1-3` (`IslandTab`)
- Test: `Tests/ShimaCoreTests/CalendarTypesTests.swift`

**Interfaces:**
- Produces:
  - `IslandTab.calendar` (case order: `music, camera, calendar`; `CaseIterable` order is used for header positions).
  - `public struct CalendarEvent: Equatable, Sendable, Identifiable { id: String; title: String; start: Date; end: Date; isAllDay: Bool; colorRGB: [Double] }` (colorRGB is `[r, g, b]`, 0...1; public memberwise `init`). `displayTitle: String` returns `title` trimmed, or `"(No title)"` when empty.
  - `public struct ReminderItem: Equatable, Sendable, Identifiable { id: String; title: String; due: Date?; isCompleted: Bool }` with the same `displayTitle`.
  - `public enum CalendarAccess: Equatable, Sendable { case notDetermined, authorized, denied }`.

- [ ] **Step 1: Write failing tests** in `CalendarTypesTests.swift`: `emptyTitleFallback` (`CalendarEvent(title: "  ")` and `ReminderItem(title: "")` give `"(No title)"`, `"Standup"` stays); `tabOrder` (`IslandTab.allCases == [.music, .camera, .calendar]`).
- [ ] **Step 2: Run** `swift test --filter CalendarTypesTests`. Expected: FAIL (types missing).
- [ ] **Step 3: Implement** the types above. Check that every existing exhaustive `switch` over `IslandTab` still compiles (`grep -rn "IslandTab" Sources Tests`; `NowPlayingLayout.tabRect` is handled in Task 4, keep it compiling with a default).
- [ ] **Step 4: Run** `swift build && swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `git add Sources/ShimaCore/CalendarTypes.swift Sources/ShimaCore/CameraModel.swift Tests/ShimaCoreTests/CalendarTypesTests.swift && git commit -m "Calendar: event, reminder and access types, calendar tab case"`

### Task 2: Month grid and left-column rules (PURE, parallel-safe with Task 3 after Task 1)

**Files:**
- Create: `Sources/ShimaCore/MonthGrid.swift`, `Sources/ShimaCore/CalendarContentRules.swift`
- Test: `Tests/ShimaCoreTests/MonthGridTests.swift`, `Tests/ShimaCoreTests/CalendarContentRulesTests.swift`

**Interfaces:**
- Consumes: `CalendarEvent`, `ReminderItem` (Task 1).
- Produces:
  - `public struct GridDay: Equatable, Sendable { date: Date; dayNumber: Int; inMonth: Bool; isToday: Bool }`
  - `public struct MonthGridModel: Equatable, Sendable { title: String; weekdaySymbols: [String]; weeks: [[GridDay]]; visibleRange: DateInterval }` (`title` is uppercase "OCTOBER 2026" from `calendar`'s locale; `visibleRange` runs from the first grid day's start to the day after the last grid day's start).
  - `public enum MonthGrid { static func make(month: Date, today: Date, calendar: Calendar) -> MonthGridModel }`
  - `public enum LeftRow: Equatable, Sendable { case event(CalendarEvent, EventPhase); case reminder(ReminderItem, overdue: Bool) }`, `public enum EventPhase: Equatable, Sendable { case running, upcoming, allDay, past }`
  - `public struct LeftColumn: Equatable, Sendable { rows: [LeftRow]; overflow: Int }`
  - `public enum CalendarContentRules`:
    - `static func events(_ events: [CalendarEvent], on day: Date, calendar: Calendar) -> [CalendarEvent]` (events overlapping that calendar day; an all-day event with `end` at exactly the next day's start does not overlap the next day)
    - `static func dotDays(events: [CalendarEvent], in grid: MonthGridModel, calendar: Calendar) -> Set<Date>` (start-of-day dates)
    - `static func leftColumn(events: [CalendarEvent], reminders: [ReminderItem], selectedDay: Date, now: Date, calendar: Calendar, cap: Int = 4) -> LeftColumn`

**Rules:** order of event rows: running (by start), upcoming (by start), all-day, past (by start). Reminders only when `selectedDay` is today; incomplete only; overdue first, then by due, then title; reminders come after all events. `rows` holds at most `cap`; `overflow` is the count beyond it.

- [ ] **Step 1: Write failing tests** (use a fixed `Calendar(identifier: .gregorian)` with `timeZone = UTC`, `locale en_US_POSIX`, `firstWeekday = 1`):
  - `octoberTwentyTwentySix`: `make(month: Oct 15 2026, today: Oct 4 2026)` has 5 weeks, first cell Sep 27 (`inMonth == false`), Oct 1 in row 0 column 4, Oct 31 in row 4 column 6, only Oct 4 has `isToday`, `title == "OCTOBER 2026"`, `weekdaySymbols.count == 7`.
  - `sixWeekMonth`: May 2026 has 6 weeks; Feb 2026 has 4.
  - `mondayFirstGrid`: with `firstWeekday = 2`, Oct 2026's first cell is Sep 28, and `weekdaySymbols.first` is Monday's symbol.
  - `dstSafeDays`: with `timeZone = America/New_York`, Nov 2026 (DST ends Nov 1) every consecutive pair of `weeks.flatMap{$0}` dates differs by one calendar day, and dayNumbers run without gaps or repeats.
  - `allDayEventEndExclusive`: an all-day event Oct 5 00:00 to Oct 6 00:00 is in `events(on: Oct 5)`, not in `events(on: Oct 6)`, and `dotDays` contains Oct 5 only.
  - `multiDayEventDotsEveryDay`: a timed event Oct 5 22:00 to Oct 7 01:00 dots Oct 5, 6, 7.
  - `leftColumnOrdersAndCaps`: at now = Oct 4 19:30 with a running event, two upcoming, one all-day, one past, two reminders (one overdue): rows are `[running, upcoming1, upcoming2, allDay]`, `overflow == 3` (past + 2 reminders); with only one event, the reminders follow with the overdue one first.
  - `noRemindersOnOtherDays`: `selectedDay` = Oct 5 while today is Oct 4 gives no reminder rows.
- [ ] **Step 2: Run** `swift test --filter "MonthGridTests|CalendarContentRulesTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** `MonthGrid.make` (use `calendar.dateInterval(of: .month)`, `calendar.date(byAdding: .day, ...)` for every day step, never add 86400 s) and the rules above.
- [ ] **Step 4: Run** the same filter. Expected: PASS. Then `swift test` for the whole suite.
- [ ] **Step 5: Commit** explicit paths, message `Calendar: month grid and left-column rules`.

### Task 3: Model, client protocol, fake and coordinator (PURE, parallel-safe with Task 2 after Task 1)

**Files:**
- Create: `Sources/ShimaCore/CalendarModel.swift`, `Sources/ShimaCore/CalendarClient.swift`, `Sources/ShimaCore/FakeCalendarClient.swift`, `Sources/ShimaCore/CalendarCoordinator.swift`
- Test: `Tests/ShimaCoreTests/CalendarModelTests.swift`, `Tests/ShimaCoreTests/CalendarCoordinatorTests.swift`

**Interfaces:**
- Consumes: Task 1 types; `MonthGrid`/`MonthGridModel.visibleRange` from Task 2 (if Task 2 is not merged yet, stub the range with `calendar.dateInterval(of: .month)` and switch after merging).
- Produces:
  - `public enum CalendarEffect: Equatable, Sendable { case requestEventsAccess, requestRemindersAccess, load(DateInterval), completeReminder(String) }`
  - `public struct CalendarModel: Equatable, Sendable` with `init(calendar: Calendar, now: Date, eventsAccess: CalendarAccess = .notDetermined, remindersAccess: CalendarAccess = .notDetermined)`; read-only state: `eventsAccess`, `remindersAccess`, `displayedMonth: Date`, `selectedDay: Date`, `events: [CalendarEvent]`, `reminders: [ReminderItem]`, `isVisible: Bool`; mutating methods, each returning `[CalendarEffect]` unless noted: `setContext(mode: IslandMode, tab: IslandTab, screenAvailable: Bool, now: Date)`, `setAccess(events: CalendarAccess, reminders: CalendarAccess, now: Date)`, `dataLoaded(events: [CalendarEvent], reminders: [ReminderItem], range: DateInterval)` (no effects), `markStale()`, `dayChanged(now: Date)`, `selectDay(_ day: Date)` (no effects), `showMonth(offset: Int)`, `goToToday(now: Date)`, `completeReminder(id: String)`, `completionFailed(_ item: ReminderItem)` (no effects), `shutdown()`.
  - `@MainActor public protocol CalendarClient: AnyObject { var eventsAccess: CalendarAccess { get }; var remindersAccess: CalendarAccess { get }; func requestEventsAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void); func requestRemindersAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void); func events(in range: DateInterval) -> [CalendarEvent]; func loadReminders(_ completion: @escaping @MainActor ([ReminderItem]) -> Void); func complete(reminderID: String) -> Bool; var onStoreChanged: (@MainActor () -> Void)? { get set }; var onDayChanged: (@MainActor () -> Void)? { get set } }`
  - `FakeCalendarClient` (settable `eventsAccess`, `remindersAccess`, fixtures `events`, `reminders`; counters `eventsRequestCount`, `remindersRequestCount`, `loadCount`, `completedIDs`; manual completion of access requests and of `loadReminders` via `completePendingAccess(_:)` / `completePendingReminders()`; `requestResult` auto-completes like `FakeCameraClient`).
  - `@Observable @MainActor public final class CalendarCoordinator` with `init(client: any CalendarClient, calendar: Calendar, now: @escaping @MainActor () -> Date)`, `private(set) var model: CalendarModel`, and passthroughs `setContext(mode:tab:screenAvailable:)`, `refreshAccess()`, `selectDay(_:)`, `showMonth(offset:)`, `goToToday()`, `complete(_ item: ReminderItem)`, `shutdown()`. It wires `onStoreChanged` to `markStale()` and `onDayChanged` to `dayChanged(now:)`, performs effects, and numbers each load: a completion whose load number is not the latest is dropped.

**Behaviour:** visible = `mode == .expanded && tab == .calendar && screenAvailable && !terminated`. Becoming visible resets `displayedMonth` and `selectedDay` to today, requests Events access once if `.notDetermined` and then (after it resolves) Reminders access once if `.notDetermined`, and loads when any store is authorized and the data is stale or the range changed. While not visible, `markStale()` only sets a flag. `setAccess` to `.denied` for a store clears that store's data. `completeReminder` removes the item locally, emits `.completeReminder(id)`; the coordinator calls `client.complete`, and on `false` calls `completionFailed`.

- [ ] **Step 1: Write failing tests.** In `CalendarModelTests` (pure, no client): `hoverNeverRequestsOrLoads` (`setContext(.expanded, .music, ...)` emits nothing); `openingRequestsEventsThenReminders` (first `setContext(.expanded, .calendar, true)` -> `[.requestEventsAccess]`; `setAccess(events: .authorized, reminders: .notDetermined)` -> `[.requestRemindersAccess, .load(range)]` in that order; a second identical call emits nothing); `loadsOnceThenOnlyWhenStale` (`markStale()` while visible -> one `.load`, while hidden -> none and the next visible open loads); `monthArrowsReloadRange` (`showMonth(offset: 1)` -> `.load` of the new visible range); `reopenResetsSelection` (select another day and month, collapse, reopen: today and current month again); `collapseWhileHiddenNeverLoads`; `dayChangedUpdatesTodayAndLoadsWhenVisible`; `revokedAccessClearsData` (load events, then `setAccess(events: .denied, ...)` -> `events.isEmpty`); `completeRemovesLocallyAndEmitsEffect`; `completionFailedRestoresItem`; `shutdownStopsEverything`. In `CalendarCoordinatorTests` with `FakeCalendarClient`: `permissionAskedOnlyOnFirstOpen` (counts 0 after hover, 1/1 after opening Calendar twice), `staleLoadCompletionIsDropped` (two loads started, complete the first reminders callback last, model keeps the second's data), `storeChangeReloadsOnlyWhenVisible`, `deniedStoreShowsStateWithoutLoad`, `completeFailureRestores` (fake `complete` returns false).
- [ ] **Step 2: Run** `swift test --filter "CalendarModelTests|CalendarCoordinatorTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** the four files per the interfaces and behaviour above.
- [ ] **Step 4: Run** the filter, then `swift test`. Expected: all pass, and `swift build` has no warnings.
- [ ] **Step 5: Commit** explicit paths, message `Calendar: model, client protocol, fake and coordinator`.

### Task 4: EventKit client, service and Calendar view (GLUE; needs Task 0's Layout table)

**Files:**
- Create: `Sources/ShimaCore/CalendarLayout.swift`, `Sources/Shima/EventKitCalendarClient.swift`, `Sources/Shima/CalendarService.swift`, `Sources/Shima/CalendarContent.swift`
- Modify: `Sources/ShimaCore/NowPlayingLayout.swift` (`tabIcon`, `settingsButton`, `tabRect` generalised by `IslandTab.allCases` index), `Sources/Shima/IslandView.swift` (third header glyph `.calendar` in `HeaderGlyph`/`HeaderGlyphShape`, `HeaderTabIcon` loops over `IslandTab.allCases` with labels, a Calendar overlay like the Camera one), `Sources/Shima/IslandPanelController.swift` (`var calendar: CalendarService?`, passed into `IslandView`), `Sources/Shima/AppDelegate.swift` (create the service, assign, shut down on terminate, refresh access on app activation), `Sources/Shima/Log.swift` (`Log.calendar`, category `calendar`), `scripts/bundle.sh` (two plist keys)
- Test: update `Tests/ShimaCoreTests/NowPlayingLayoutTests.swift` for the new icon constants; add `Tests/ShimaCoreTests/CalendarLayoutTests.swift` (each rect lies inside 400 x 200, none overlaps the header notch zone x 110.5..289.5, the grid cells for 6 weeks fit above y 200)

**Interfaces:**
- Consumes: everything from Tasks 1-3 and the spec's Layout table.
- Produces: `CalendarLayout` constants (rects and font sizes from the table, in the island's top-left local coordinates, same style as `NowPlayingLayout`); `CalendarService` (`@Observable @MainActor`, owns `coordinator: CalendarCoordinator`, `fake: FakeCalendarClient?`, observers for `NSApplication.didBecomeActiveNotification` to `coordinator.refreshAccess()`, and registers `state.onCameraContextChange`-style delivery: reuse the same `AppState` context hook by adding a second observer list, see below); `CalendarContent` (SwiftUI overlay, takes the service and `AppState`).

**Notes:**
- `AppState.onCameraContextChange` has a single owner today. Rename it to `onTabContextChange` and make it a list of handlers (`addTabContextObserver(_:)`), keep Camera working and keep its tests passing; Calendar registers its own. This is the only cross-cutting change in this task; do it first and run the camera tests.
- `EventKitCalendarClient`: one `EKEventStore`; access mapping `.fullAccess` -> authorized, `.notDetermined` -> notDetermined, `.denied`/`.restricted`/`.writeOnly` -> denied (events); `.fullAccess` -> authorized for reminders; requests use `requestFullAccessToEvents`/`requestFullAccessToReminders`, results hopped to the main actor; `events(in:)` via `predicateForEvents`, mapping `calendar.cgColor` to sRGB `[r, g, b]`; `loadReminders` via `predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday, calendars: nil)` (overdue plus due today; undated excluded); `complete(reminderID:)` fetches `calendarItem(withIdentifier:) as? EKReminder`, sets `isCompleted`, saves with `commit: true`, returns success; observers for `.EKEventStoreChanged` and `.NSCalendarDayChanged` call the `on...` handlers.
- Denied state UI: one line per store ("Calendar access is off" / "Reminders access is off") and a button that opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars` / `Privacy_Reminders` through the same `NSWorkspace.open` path the Settings window uses.
- The tab never starts work while hidden: `CalendarContent` is only inserted when `state.mode == .expanded && state.selectedTab == .calendar`, like Camera.

- [ ] **Step 1:** Do the `onTabContextChange` refactor; run `swift test` (all existing camera tests must pass unchanged in meaning). Commit `Tab context observers can be many`.
- [ ] **Step 2: Failing tests** for `CalendarLayoutTests` and the updated `NowPlayingLayoutTests` (four icons: Home, Music, Camera, Calendar with the table's x positions; none overlaps x 110.5..289.5). Run, expect FAIL.
- [ ] **Step 3: Implement** `CalendarLayout`, the generalised `tabRect`, and the header changes. Run the layout tests: PASS.
- [ ] **Step 4: Implement** the EventKit client, `CalendarService`, `CalendarContent`, the wiring and the plist keys. `swift build` must be warning-free.
- [ ] **Step 5: Run** `swift build && swift test`. Expected: pass.
- [ ] **Step 6: Commit** in small explicit-path commits (layout, client and service, view and wiring).

### Task 5: Fake mode, drive commands and checks (SCRIPT)

**Files:**
- Modify: `Sources/Shima/CalendarService.swift` (fake mode), `scripts/drive.swift` (new `fake-calendar` step), `scripts/verify-view-layout.sh` (add `Sources/Shima/CalendarContent.swift`, `CalendarService.swift`, `EventKitCalendarClient.swift` to its `sources` array), `scripts/view-layout-check.swift` (calendar render cases), `scripts/island-input-geometry.sh` (print the calendar header x)
- Create: `scripts/verify-calendar.sh`

**Behaviour:**
- `SHIMA_FAKE_CALENDAR=1` makes `CalendarService` use `FakeCalendarClient` with fixtures: today's date with one running event (19:15-20:00), two later events, one all-day, two reminders (one overdue), events on three other days in the month. It never touches EventKit.
- `swift scripts/drive.swift "fake-calendar <cmd>"` posts the distributed notification `local.shima.fake-calendar` (object = cmd). Commands: `ping` (logs `calendar fake ping`), `allowed`, `denied`, `empty`, `full` (six-week month and more than four rows), `changed` (fires `onStoreChanged`), `daychanged` (fires `onDayChanged`). Every command logs `calendar fake <cmd>`; model effects log `calendar load ...`, `calendar request events|reminders`, `calendar complete <id>` under category `calendar`.
- `view-layout-check.swift`: render `CalendarContent` offscreen for `allowed`, `denied`, `empty`, `full` and assert: nothing draws outside 400 x 200; the six-week grid's last row is inside the island; text rows do not overlap the notch zone; the existing black-region rule (0..32 live, 0..<165 expanded) still passes for Music and Camera.
- `verify-calendar.sh` (model it on `verify-camera.sh`: finds the `dist` pid, refuses to click unless the fake log line appears): with `SHIMA_FAKE_CALENDAR=1 scripts/run.sh` running, it hovers open, asserts **no** `calendar request` or `calendar load` log lines while Music is selected, clicks the Calendar header icon, asserts exactly one events request and one load, clicks month arrows (new load each), `fake-calendar denied` (no load, denied state logged), `allowed`, `changed` while open (one load) and while collapsed (none until reopened), `daychanged`, collapse and re-hover (back on Music, no calls). Keep pointer sequences under 2 minutes and announce them.

- [ ] **Step 1:** Implement fake mode and the `drive.swift` step; `swift build`.
- [ ] **Step 2:** Extend `verify-view-layout.sh` and `view-layout-check.swift`; run `scripts/verify-view-layout.sh`. Expected: prints PASS lines for all calendar cases and the existing ones.
- [ ] **Step 3:** Write `scripts/verify-calendar.sh`; start `SHIMA_FAKE_CALENDAR=1 SHIMA_FAKE_SPOTIFY=paused scripts/run.sh`, run `scripts/verify-calendar.sh`, expect `PASS`.
- [ ] **Step 4:** Run the regression set with the same fake app: `scripts/verify-alignment.sh --expanded`, `scripts/verify-focus.sh --clicks`, `scripts/verify-idle.sh` (add `--playing` only with fake Spotify playing) and `scripts/verify-camera.sh` (restart with `SHIMA_FAKE_CAMERA=1` for this one). Expected: all pass; idle CPU unchanged. Kill the app by pid when done (never `pkill -x Shima`).
- [ ] **Step 5: Commit** explicit paths, message `Calendar: fake mode, drive command and verification scripts`.

### Task 6: Review and acceptance (CLAUDE + HUMAN, not Codex)

- Whole-branch review by a fresh reviewer (not the implementer) against the spec and Global Constraints; fixes go through a short correction wave and a scoped re-review, as for M1.
- Human checks, recorded in `docs/superpowers/calendar-acceptance.md`: first-open Calendar prompt then Reminders prompt; real events and reminders appear (including Google events if that account is in macOS Calendar); completing a reminder shows done in Reminders; denying then allowing in System Settings recovers on return to shima; no Calendar or Reminders access shows while on Music.
- Update `CLAUDE.md` Status and the memory index after acceptance.

## Self-review notes

- Spec coverage: tab and header (Tasks 0, 4); left column rules (2); grid, dots, today circle, month nav, title reset (2, 3, 4); reminder completion (3, 4); first-open permissions and denied states (3, 4); 400 x 200 fit with six weeks (2, 4, 5); event-driven refresh (3, 4, 5); fake mode and checks (5); human checks (6). Non-goals have no tasks, intentionally.
- Names used across tasks match: `CalendarModel`, `CalendarCoordinator`, `CalendarClient`, `FakeCalendarClient`, `CalendarEffect`, `MonthGridModel`, `LeftColumn`, `CalendarLayout`, `CalendarService`, `CalendarContent`, `onTabContextChange`.
