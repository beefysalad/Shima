# Calendar and Reminders tab Implementation Plan

> **For agentic workers (Codex):** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax. Read `CLAUDE.md` first: it holds the project rules and gotchas. Work in a worktree `.worktrees/calendar` on branch `calendar` (`git worktree add .worktrees/calendar -b calendar`). Task labels: **PURE** (ShimaCore, tests, no AppKit/EventKit), **GLUE** (Shima app), **SCRIPT**, **HUMAN/CLAUDE** (not for Codex; skip and report when you reach one).

**Goal:** A Calendar tab in the open island showing the selected day's events and due reminders and a month grid, from the macOS Calendar and Reminders stores.

**Architecture:** Same shape as Camera. Pure `CalendarModel` reducer + `CalendarCoordinator` + `CalendarClient` protocol (with a fake) in `ShimaCore`; an EventKit client, a service and a SwiftUI overlay in `Shima`. Refresh is event-driven (`EKEventStoreChanged`, `NSCalendarDayChanged`), only while the tab is visible.

**Tech Stack:** Swift 6 toolchain, SwiftPM only, Swift Testing (`import Testing`, no XCTest), EventKit, SwiftUI in the existing `NSPanel`. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-11-23-calendar-reminders-design.md`. Mirror these existing files when in doubt: `Sources/ShimaCore/{CameraModel,CameraClient,FakeCameraClient,CameraCoordinator}.swift`, `Sources/Shima/{CameraService,CameraContent}.swift`, `Tests/ShimaCoreTests/CameraTests.swift`, `scripts/verify-camera.sh`.

## Ownership (decided 2026-11-23)

Codex does logic, wiring and scripts. **Claude does every view, layout constant, header change and animation, and the visual comparison against the mockup** (the user does not trust Codex to reproduce the mockup). Codex: do only tasks labelled Codex; when you reach a Claude task, stop, report, and wait. Mockup approved by the user 2026-11-23.

| Task | Owner |
|---|---|
| 0 Mockup and layout table | Claude (done, approved) |
| 1 Types and tab case | Codex |
| 2 Month grid and left-column rules | Codex |
| 3 Model, client protocol, fake, coordinator | Codex |
| 4a EventKit client, service, plist, wiring | Codex |
| 4b Calendar UI: layout numbers, header icons, glyph, view, denied state | **Claude** |
| 5a Fake mode, drive command, verify-calendar.sh, regression runs | Codex |
| 5b Offscreen render checks and mockup comparison | **Claude** |
| 6 Review and acceptance | Claude and the user |

Order: 1, then 2 and 3 in parallel, then 4a; Claude does 4b after 4a; then 5a and 5b; then 6.

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

### Task 0: Mockup and layout table (Claude, done, approved by the user 2026-11-23)

`mockup/index.html` now has the Calendar tab and the spec ends with the "Layout table" (all rects, font sizes, the four header icon positions at x 12/36/60/84 that clear the notch zone). Approved by the user 2026-11-23; the numbers are in the spec's Layout table (used by Claude in Task 4b).

### Task 1: Types and the Calendar tab case (PURE, Codex)

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

### Task 2: Month grid and left-column rules (PURE, Codex; parallel-safe with Task 3 after Task 1)

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

### Task 3: Model, client protocol, fake and coordinator (PURE, Codex; parallel-safe with Task 2 after Task 1)

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

### Task 4a: EventKit client, service and wiring (GLUE, Codex)

**Files:**
- Create: `Sources/Shima/EventKitCalendarClient.swift`, `Sources/Shima/CalendarService.swift`
- Modify: `Sources/ShimaCore/AppState.swift` (tab-context observers), `Sources/Shima/CameraService.swift` (use the new observer API), `Sources/Shima/IslandPanelController.swift` (only `var calendar: CalendarService?`; Claude passes it to the view in 4b), `Sources/Shima/AppDelegate.swift`, `Sources/Shima/Log.swift` (`Log.calendar`, category `calendar`), `scripts/bundle.sh` (two plist keys)
- Test: `Tests/ShimaCoreTests/AppStateTabObserverTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces: `AppState.addTabContextObserver(_ handler: @escaping @MainActor (IslandMode, IslandTab) -> Void)` (replaces the single `onCameraContextChange`; every handler is called synchronously on each `mode`/`selectedTab` change, and once on registration with the current values; the collapse-resets-to-Music rule stays); `CalendarService` (`@Observable @MainActor`, `let coordinator: CalendarCoordinator`, `init(state: AppState, environment: [String: String])`, `func shutdown()`); `EventKitCalendarClient: CalendarClient`.

**Notes:**
- Do the observer refactor first; all existing camera tests must keep passing unchanged in meaning.
- `EventKitCalendarClient`: one `EKEventStore`; events access mapping `.fullAccess` -> authorized, `.notDetermined` -> notDetermined, `.denied`/`.restricted`/`.writeOnly` -> denied; reminders `.fullAccess` -> authorized, others as above; requests use `requestFullAccessToEvents` / `requestFullAccessToReminders`, results hopped to the main actor; `events(in:)` via `predicateForEvents`, mapping `calendar.cgColor` to sRGB `[r, g, b]`; `loadReminders` via `predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday, calendars: nil)` (overdue plus due today; undated excluded); `complete(reminderID:)` fetches `calendarItem(withIdentifier:) as? EKReminder`, sets `isCompleted`, saves with `commit: true`, returns success; observers for `.EKEventStoreChanged` and `.NSCalendarDayChanged` call `onStoreChanged` / `onDayChanged`.
- `CalendarService` registers one tab-context observer that forwards `(mode, tab)` to `coordinator.setContext(mode:tab:screenAvailable:)`, tracks screen sleep/wake and lock like `CameraService` for `screenAvailable`, and calls `coordinator.refreshAccess()` on `NSApplication.didBecomeActiveNotification`.
- Plist keys in `scripts/bundle.sh`: `NSCalendarsFullAccessUsageDescription`, `NSRemindersFullAccessUsageDescription`.

- [ ] **Step 1: Failing tests** `AppStateTabObserverTests`: two observers both receive each change; an observer registered late gets the current context once; collapse from Calendar resets to Music and delivers a single collapsed-Music context (same expectation the camera already has). Run: FAIL.
- [ ] **Step 2: Implement** the observer API and migrate `CameraService`; `swift test` passes. Commit `Tab context observers can be many`.
- [ ] **Step 3: Implement** the EventKit client, the service, the `AppDelegate` wiring (create, assign `islandController.calendar`, shut down in `applicationShouldTerminate`), `Log.calendar` and the plist keys. `swift build` warning-free; `swift test` passes.
- [ ] **Step 4: Commit** in small explicit-path commits (client, service and wiring, plist).
- [ ] **Step 5: Report** to the user that 4b (Claude) can start.

### Task 4b: Calendar UI (VIEW, **Claude**)

**Files:** Create `Sources/ShimaCore/CalendarLayout.swift`, `Sources/Shima/CalendarContent.swift`; modify `Sources/ShimaCore/NowPlayingLayout.swift` (header icon positions x 12/36/60/84, `tabRect` by `IslandTab.allCases` index), `Sources/Shima/IslandView.swift` (calendar glyph, header loop, overlay, pass `calendar`), `Sources/Shima/IslandPanelController.swift` (pass `calendar` into `IslandView`); tests `Tests/ShimaCoreTests/CalendarLayoutTests.swift` and the updated `NowPlayingLayoutTests.swift`.
Everything is taken from the spec's Layout table and `mockup/index.html`; the view is only inserted when `state.mode == .expanded && state.selectedTab == .calendar` (like Camera). Claude verifies each state against headless screenshots of the mockup (Task 5b).

### Task 5a: Fake mode, drive command and checks (SCRIPT, Codex)

**Files:** Modify `Sources/Shima/CalendarService.swift` (fake mode), `scripts/drive.swift` (new `fake-calendar` step); create `scripts/verify-calendar.sh`.

**Behaviour:**
- `SHIMA_FAKE_CALENDAR=1` makes `CalendarService` use `FakeCalendarClient` with fixtures: today's date with one running event (9:30-10:00), one upcoming (11:00-12:00), two reminders (one overdue), events on days 3, 9, 13, 27 of the month. It never touches EventKit.
- `swift scripts/drive.swift "fake-calendar <cmd>"` posts the distributed notification `local.shima.fake-calendar` (object = cmd). Commands: `ping` (logs `calendar fake ping`), `allowed`, `denied`, `empty`, `full` (six-week month and more than four rows), `changed` (fires `onStoreChanged`), `daychanged` (fires `onDayChanged`). Every command logs `calendar fake <cmd>`; effects log `calendar load ...`, `calendar request events|reminders`, `calendar complete <id>` under category `calendar`.
- `verify-calendar.sh` (model it on `verify-camera.sh`: finds the `dist` pid, refuses to click unless the fake log line appears): with `SHIMA_FAKE_CALENDAR=1 scripts/run.sh` running, it hovers open, asserts **no** `calendar request` or `calendar load` log lines while Music is selected, clicks the Calendar header icon (coordinates from `scripts/island-input-geometry.sh`; extend that script to print the calendar icon x), asserts exactly one events request and one load, clicks month arrows (a new load each), `fake-calendar denied` (no load, denied state logged), `allowed`, `changed` while open (one load) and while collapsed (none until reopened), `daychanged`, collapse and re-hover (back on Music, no calls). Keep pointer sequences under 2 minutes and announce them.

- [ ] **Step 1:** Implement fake mode and the `drive.swift` step; `swift build`.
- [ ] **Step 2:** Write `scripts/verify-calendar.sh`; start `SHIMA_FAKE_CALENDAR=1 SHIMA_FAKE_SPOTIFY=paused scripts/run.sh`, run it, expect `PASS`. (Needs Task 4b merged for the icon to exist; if it is not, report and wait.)
- [ ] **Step 3:** Regression set with the same fake app: `scripts/verify-alignment.sh --expanded`, `scripts/verify-focus.sh --clicks`, `scripts/verify-idle.sh`, and `scripts/verify-camera.sh` (restart with `SHIMA_FAKE_CAMERA=1` for this one). Expected: all pass, idle CPU unchanged. Kill the app by pid (never `pkill -x Shima`).
- [ ] **Step 4: Commit** explicit paths, message `Calendar: fake mode, drive command and verify script`.

### Task 5b: Offscreen render checks and mockup comparison (VIEW, **Claude**)

Adds `CalendarContent.swift`, `CalendarService.swift`, `EventKitCalendarClient.swift` to the `sources` array in `scripts/verify-view-layout.sh`, calendar cases (`allowed`, `denied`, `empty`, `full`) to `scripts/view-layout-check.swift` (nothing outside 400 x 200, six-week grid inside the island, nothing but header icons in y < 34, existing black-region rule still passes), writes the renders to PNG and compares each against a headless-Chrome screenshot of the matching mockup state (the harness used on 2026-11-23); mismatches are fixed in 4b until they agree.

### Task 6: Review and acceptance (Claude and the user)

- Whole-branch review by a fresh reviewer (not the implementer) against the spec and Global Constraints; fixes through a short correction wave and a scoped re-review, as for M1.
- Human checks, recorded in `docs/superpowers/calendar-acceptance.md`: first-open Calendar prompt then Reminders prompt; real events and reminders appear (including Google events if that account is in macOS Calendar); completing a reminder shows done in Reminders; denying then allowing in System Settings recovers on return to shima; no Calendar or Reminders access shows while on Music.
- Update `CLAUDE.md` Status and the memory index after acceptance.

## Self-review notes

- Spec coverage: tab and header (Tasks 0, 4); left column rules (2); grid, dots, today circle, month nav, title reset (2, 3, 4); reminder completion (3, 4); first-open permissions and denied states (3, 4); 400 x 200 fit with six weeks (2, 4, 5); event-driven refresh (3, 4, 5); fake mode and checks (5); human checks (6). Non-goals have no tasks, intentionally.
- Names used across tasks match: `CalendarModel`, `CalendarCoordinator`, `CalendarClient`, `FakeCalendarClient`, `CalendarEffect`, `MonthGridModel`, `LeftColumn`, `CalendarLayout`, `CalendarService`, `CalendarContent`, `addTabContextObserver`.
