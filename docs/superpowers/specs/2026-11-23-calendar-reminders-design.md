# Calendar and Reminders tab (the "DynaGlance" idea)

Status: approved by the user 2026-11-23 (design agreed in conversation; this file writes it down). Reference image: DynaGlance, an expanded calendar with today's date, the current event and a month grid. Order: built before `2026-11-23-device-popups-design.md`.

## Intent

The open island gets a third tab, Calendar, that answers "what is on today and what is due?" without opening the Calendar or Reminders apps. Data comes from the macOS Calendar and Reminders stores through EventKit, so anything the user already syncs there (iCloud, Google, Exchange) shows up with no accounts or keys inside shima.

## Goals

- A Calendar tab in the header strip, as the third outlined icon after Home, Music, Camera.
- Left column: the selected day (today by default) as "SUN | OCT" over a large day number, then up to four rows: events first (the running or next one first, with a colour bar, title and time range), then incomplete reminders due that day or overdue (when the selected day is today). More than four rows shows "+N more".
- Right column: month title ("OCTOBER 2026"), previous and next month arrows, a weekday header row and the day grid. Today's number is the accent colour. A small dot marks days with at least one event. Clicking a day selects it. Clicking the month title returns to today's month and day.
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


## Layout table (Task 0 output, real points in the 400 x 200 island, top-left origin)

Mockup: `mockup/index.html` (Calendar tab, "Jump to state" > Calendar; Simulate > Calendar and Reminders for denied and six-week states). The mockup draws at its own larger scale; these are the real values. Colours: accent `#E07A4F` (today circle, weekday and month name, overdue), done blue `#86AEF7` (event dots), selection ring white at 55%, text white / 62% / 52%.

- **Header icons (replaces today's 14/42/70 positions):** four hit areas 22 x 22 at y 5, x = 12 (Home), 36 (Music), 60 (Camera), 84 (Calendar). The fourth ends at x 106, clear of the notch zone 110.5..289.5. Glyph 14 pt, stroke as the existing header glyphs. Calendar glyph (24-unit): `rect x4 y5 w16 h15 r2.5`, `M4 10h16`, `M9 3v4`, `M15 3v4`.
- **Left column (x 18..176):** weekday and month line rect (18, 38, 158, 14), 11 pt semibold, weekday in accent, thin divider, month in 62% white; day number rect (18, 50, 158, 36), 30 pt bold; rows start y 92, row height 17, pitch 19, at most 4 (ends y 168); "+N more" rect (18, 170, 158, 12), 10 pt, 52% white.
- **Event row:** 2 pt wide colour bar full row height at x 18; title from x 26, 11.5 pt semibold, tail truncation; time range right-aligned to x 176, 10 pt tabular digits, 62% white. The running event shows `Now · 9:30 – 10:00` in the event colour, semibold.
- **Reminder row:** 11 pt outlined circle at x 18 (tap target 18 x 17), title from x 34, right text 10 pt ("Today", or "Overdue" in accent). Completed: circle fills with done blue and a check, row fades out over 0.25 s then is removed.
- **Denied state:** two boxes (18, 92, 158, 40) and (18, 138, 158, 40), white 7.5% fill, radius 8: bold 11 pt line ("Calendar access is off" / "Reminders access is off") and an "Open Settings" button 18 pt high, radius 6, 10.5 pt.
- **Right column (x 196..386):** title rect (196, 38, 150, 18), 12 pt bold, month name in accent, year in white (clicking it returns to today); previous/next arrows 18 x 18 hit areas at x 350 and 368, y 38; weekday letters rect (196, 58, 190, 12), 9.5 pt semibold, 52% white; day grid origin (196, 72), cell 27.14 x 19 (190 / 7 wide), up to 6 rows, so it ends at y 186 at most (5-week months end at 167). Day numbers 11 pt semibold tabular; days outside the month 52% white, regular. Today: the number in the accent colour, bold (no circle: the circle was cramped, 2026-11-23). Selected (not today): 1.5 pt ring. Event dot 3 pt at the cell's bottom centre, done blue (the dot means "has events", not "today").
- **Empty day:** "Nothing scheduled", 11.5 pt, 52% white, at (18, 92).
- **Layout rule:** nothing but the header icons occupies y < 34, so the notch zone stays clear.
