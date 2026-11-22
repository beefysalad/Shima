# Calendar and Reminders tab (the "DynaGlance" idea)

Status: approved by the user 2026-11-23 (design agreed in conversation; this file writes it down). Reference image: DynaGlance, an expanded calendar with today's date, the current event and a month grid. Order: built before `2026-11-23-device-popups-design.md`.

## Intent

The open island gets a third tab, Calendar, that answers "what is on today and what is due?" without opening the Calendar or Reminders apps. Data comes from the macOS Calendar and Reminders stores through EventKit, so anything the user already syncs there (iCloud, Google, Exchange) shows up with no accounts or keys inside shima.

## Goals

- A Calendar tab in the header strip, as the third outlined icon after Home, Music, Camera.
- Left column: the selected day (today by default) as "SUN | OCT" over a large day number, then up to four rows: events first (the running or next one first, with a colour bar, title and time range), then incomplete reminders due that day or overdue (when the selected day is today). More than four rows shows "+N more".
- Right column: month title ("OCTOBER 2026"), previous and next month arrows, a weekday header row and the day grid. Today is a filled accent circle. A small dot marks days with at least one event. Clicking a day selects it. Clicking the month title returns to today's month and day.
- A reminder row has a tap target that completes it (writes back to Reminders). Nothing else is written.
- Permissions are asked on first opening the tab, never at launch: Calendar full access, then Reminders full access. Denied or restricted shows one inline line per section and a button that opens the matching System Settings pane. Write-only calendar access counts as denied.
- Everything fits the existing 400 x 200 island, including months that span six weeks.

## Non-goals

Creating or editing events; event alerts or a collapsed-island pop-up for an event about to start (a later use of the peek mechanism built in the device pop-ups milestone); week or agenda views; opening events in Calendar.app; per-calendar filtering; a Settings page for this tab.

## Anti-goals

Polling or a repeating timer while idle. A permission prompt at launch or on hover. Reading calendars while the tab is not visible. A third-party dependency.

## Constraints from the project

- Mockup first: `mockup/index.html` gets the Calendar tab and the approved layout before any Swift UI. The real UI must match it (project rule).
- Logic in `ShimaCore` with Swift Testing tests, no AppKit and no EventKit import there. EventKit lives in `Shima`.
- The island root `ZStack` must not grow; use overlays and explicit frames (gotcha). The Calendar panel is an overlay like Camera's.
- Event-driven refresh only: `EKEventStoreChanged` marks data stale, the next time the tab is visible it reloads; `NSCalendarDayChanged` marks today stale. No timers.
- The terminal has no Screen Recording: verify with logs, the window list, CGEvent input and offscreen renders.

## Approaches considered

1. **EventKit through a `CalendarClient` protocol, pure model plus coordinator, like Camera (chosen).** Same shape as `CameraClient`/`CameraModel`/`CameraCoordinator`, so it is testable with a fake and follows the project's pattern. Trade-off: some ceremony for a read-mostly feature.
2. EventKit read directly from SwiftUI views. Less code, but untestable, and views would own permission and refresh logic, which the project already learned to avoid with Camera.
3. Shell out to `icalBuddy` or AppleScript. Rejected: external dependency or Apple Events, slower, no change notifications.

The user chose to use the Calendar and Reminders already on the Mac, which is approach 1's data source.

## Design

### Pure layer (`ShimaCore`)

- `IslandTab` gains `.calendar` (raw value "calendar").
- `CalendarEvent { id, title, start, end, isAllDay, colorRGB }` and `ReminderItem { id, title, due: Date?, isCompleted }`. Both `Equatable, Sendable, Identifiable`.
- `CalendarAccess`: `.notDetermined, .authorized, .denied` per store (events, reminders).
- `MonthGrid.make(month:today:calendar:) -> MonthGridModel` returns title text, weekday symbols (respecting `calendar.firstWeekday`), and the weeks as rows of `GridDay { date, dayNumber, inMonth, isToday }`. Number of rows is the number of weeks the month needs (4 to 6).
- `CalendarContentRules`: `currentOrNext(events:now:)`, `eventDots(events:in month)`, `leftRows(events:reminders:selectedDay:now:cap:)` returning rows plus an overflow count; ordering and the cap of 4 live here.
- `CalendarModel` (pure reducer, like `CameraModel`): inputs `setContext(mode, tab, screenAvailable)`, `setAccess(events:reminders:)`, `dataLoaded`, `markStale`, `selectDay`, `showMonth(offset)`, `goToToday`. Effects: `requestEventsAccess`, `requestRemindersAccess`, `load(range)`, `completeReminder(id)`. It asks for access once, only when visible (`.expanded`, tab `.calendar`, screen available), asks Reminders only after Calendar resolves, loads when visible and (never loaded or stale or range changed).
- `CalendarClient` (protocol, `@MainActor`): `eventsAccess`, `remindersAccess`, `requestEventsAccess(completion)`, `requestRemindersAccess(completion)`, `events(in: DateInterval) -> [CalendarEvent]`, `reminders() -> async [ReminderItem]` (EventKit's reminder fetch is async), `complete(reminderID)`, `onStoreChanged` and `onDayChanged` handlers.
- `FakeCalendarClient` records calls and lets tests complete access requests manually.
- `CalendarCoordinator` (`@Observable @MainActor`) owns the model and the client and performs effects, like `CameraCoordinator`. It is the only thing views read.

### Glue (`Shima`)

- `CalendarService` (EventKit client, observers for `.EKEventStoreChanged` and `.NSCalendarDayChanged`, activation refresh of access like `CameraService`). Holds one `EKEventStore`. Fake mode `SHIMA_FAKE_CALENDAR=1` uses `FakeCalendarClient` with fixed fixtures and logs `calendar fake ...` lines; `drive.swift` gets `fake-calendar <cmd>` (distributed notification `local.shima.fake-calendar`): `ping`, `denied`, `allowed`, `changed`, `daychanged`, `empty`, `full` (six-week month plus many events).
- `CalendarContent` SwiftUI overlay (like `CameraContent`) laid out from new `CalendarLayout` constants in `ShimaCore` (same style as `NowPlayingLayout`). `HeaderTabIcon` gets the third glyph (outlined calendar, 24-unit path like the others) and `NowPlayingLayout.tabRect` generalises to an index.
- Info.plist (in `scripts/bundle.sh`): `NSCalendarsFullAccessUsageDescription` and `NSRemindersFullAccessUsageDescription`.
- Logs under category `calendar`.

### Behaviour rules

- Collapse resets the selected tab to Music (existing rule), so reopening never reads calendars until the user picks Calendar again.
- Selected day and displayed month reset to today every time the tab opens.
- `markStale` while the tab is open reloads immediately; while closed it only sets the flag.
- Completing a reminder removes it from the list at once and writes; a failed write puts it back and logs.

## What is left to the builder

Exact pixel layout (it is fixed by the approved mockup), animation, glyph drawing, and the tests' exact names, within the rules above.

## Verification

Automated: `swift test`, offscreen render check of the Calendar panel (extend `verify-view-layout.sh`, six-week month fits, black 0..<165 rule still true outside the panel), fake-mode run with `drive.swift` (open tab, month arrows, denied state, change and day-change refresh, tab clicks via CGEvent), `verify-focus.sh`, `verify-idle.sh` (no CPU or timers added while idle), logs showing no EventKit reads while Music is the tab.
Human (cannot be done from the terminal): the two real permission prompts, real events and reminders showing, completing a reminder and seeing it in Reminders, Google calendar events appearing if the Google account is added in macOS Calendar. Recorded in `docs/superpowers/calendar-acceptance.md`.
