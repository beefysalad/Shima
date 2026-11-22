import AppKit
import CoreGraphics
import Observation
import ShimaCore

/// Keeps EventKit work gated on the selected tab and screen availability.
@Observable @MainActor final class CalendarService: NSObject {
    let coordinator: CalendarCoordinator
    private let eventKit: EventKitCalendarClient?
    private let fake: CalendarFixtureClient?
    @ObservationIgnored private weak var state: AppState?
    @ObservationIgnored private var tabContextObserver: UUID?
    private var screenAwake: Bool
    private var systemAwake = true
    private var locked: Bool
    private var sessionActive: Bool

    init(state: AppState, environment: [String: String]) {
        if environment["SHIMA_FAKE_CALENDAR"] == "1" {
            let fixture = CalendarFixtureClient()
            eventKit = nil
            fake = fixture
            coordinator = CalendarCoordinator(client: fixture, calendar: fixture.calendar, now: { fixture.now })
        } else {
            let client = EventKitCalendarClient()
            eventKit = client
            fake = nil
            coordinator = CalendarCoordinator(client: client, calendar: .autoupdatingCurrent, now: { Date() })
        }
        self.state = state
        screenAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        locked = (session?["CGSSessionScreenIsLocked"] as? Bool) == true
        sessionActive = (session?[kCGSessionOnConsoleKey as String] as? Bool) ?? true
        super.init()

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screenSlept), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenWoke), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemSlept), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemWoke), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionBecameActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)
        if fake != nil {
            distributed.addObserver(self, selector: #selector(fakeControl(_:)), name: .init("local.shima.fake-calendar"),
                                    object: nil, suspensionBehavior: .deliverImmediately)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)

        tabContextObserver = state.addTabContextObserver { [weak self] mode, tab in
            self?.setContext(mode: mode, tab: tab)
        }
    }

    func shutdown() {
        if let tabContextObserver {
            state?.removeTabContextObserver(tabContextObserver)
            self.tabContextObserver = nil
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        coordinator.shutdown()
        eventKit?.shutdown()
    }

    private func setContext(mode: IslandMode, tab: IslandTab) {
        coordinator.setContext(mode: mode, tab: tab,
                               screenAvailable: screenAwake && systemAwake && !locked && sessionActive)
    }

    private func updateContext() {
        guard let state else { return }
        setContext(mode: state.mode, tab: state.selectedTab)
    }

    @objc private func screenSlept() { screenAwake = false; updateContext() }
    @objc private func screenWoke() { screenAwake = true; updateContext() }
    @objc private func systemSlept() { systemAwake = false; updateContext() }
    @objc private func systemWoke() { systemAwake = true; updateContext() }
    @objc private func screenLocked() { locked = true; updateContext() }
    @objc private func screenUnlocked() { locked = false; updateContext() }
    @objc private func sessionResigned() { sessionActive = false; updateContext() }
    @objc private func sessionBecameActive() { sessionActive = true; updateContext() }
    @objc private func appBecameActive() { coordinator.refreshAccess() }

    @objc nonisolated private func fakeControl(_ note: Notification) {
        guard let command = note.object as? String else { return }
        MainActor.assumeIsolated {
            guard let fake else { return }
            Log.calendar.info("calendar fake \(command, privacy: .public)")
            switch command {
            case "allowed", "denied":
                let access: CalendarAccess = command == "allowed" ? .authorized : .denied
                fake.fixture.eventsAccess = access
                fake.fixture.remindersAccess = access
                coordinator.refreshAccess()
                let model = coordinator.model
                Log.calendar.info("calendar access events=\(String(describing: model.eventsAccess), privacy: .public) reminders=\(String(describing: model.remindersAccess), privacy: .public)")
            case "empty":
                fake.fixture.events = []
                fake.fixture.reminders = []
                fake.onStoreChanged?()
            case "full":
                fake.showFullMonth()
                fake.onDayChanged?()
                coordinator.goToToday()
            case "changed": fake.onStoreChanged?()
            case "daychanged": fake.onDayChanged?()
            default: break
            }
        }
    }
}

@MainActor private final class CalendarFixtureClient: CalendarClient {
    let fixture = FakeCalendarClient()
    let calendar = Calendar.current
    private(set) var now: Date = Date()

    init() {
        now = clock(on: now, hour: 9, minute: 45)
        populate(full: false)
    }

    var eventsAccess: CalendarAccess { fixture.eventsAccess }
    var remindersAccess: CalendarAccess { fixture.remindersAccess }
    var onStoreChanged: (@MainActor () -> Void)? {
        get { fixture.onStoreChanged }
        set { fixture.onStoreChanged = newValue }
    }
    var onDayChanged: (@MainActor () -> Void)? {
        get { fixture.onDayChanged }
        set { fixture.onDayChanged = newValue }
    }

    func requestEventsAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void) {
        Log.calendar.info("calendar request events")
        fixture.requestEventsAccess(completion)
    }

    func requestRemindersAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void) {
        Log.calendar.info("calendar request reminders")
        fixture.requestRemindersAccess(completion)
    }

    func events(in range: DateInterval) -> [CalendarEvent] {
        Log.calendar.info("calendar load \(range.start.ISO8601Format(), privacy: .public) to \(range.end.ISO8601Format(), privacy: .public)")
        return fixture.events(in: range)
    }

    func loadReminders(_ completion: @escaping @MainActor ([ReminderItem]) -> Void) {
        // When events access is denied, this is the only client call for the load.
        if eventsAccess != .authorized { Log.calendar.info("calendar load reminders") }
        fixture.loadReminders(completion)
    }

    func complete(reminderID: String) -> Bool {
        Log.calendar.info("calendar complete \(reminderID, privacy: .public)")
        return fixture.complete(reminderID: reminderID)
    }

    func showFullMonth() {
        // Keep the user's first weekday when finding a month that actually needs six rows.
        let month = calendar.dateInterval(of: .month, for: now)!.start
        if let fullMonth = (0..<24).lazy.compactMap({ self.calendar.date(byAdding: .month, value: $0, to: month) })
            .first(where: { MonthGrid.make(month: $0, today: $0, calendar: calendar).weeks.count == CalendarLayout.maxWeeks }) {
            now = clock(on: calendar.date(byAdding: .day, value: 14, to: fullMonth)!, hour: 9, minute: 45)
        }
        populate(full: true)
    }

    private func clock(on day: Date, hour: Int, minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func populate(full: Bool) {
        let month = calendar.dateInterval(of: .month, for: now)!.start
        let priorDay = calendar.date(byAdding: .day, value: -1, to: now)!
        fixture.events = [
            event("running", "Design review", on: now, from: 9, minute: 30, to: 10),
            event("upcoming", "Project sync", on: now, from: 11, to: 12),
        ]
        // Today's two events already supply its month-grid dot.
        fixture.events += [3, 9, 13, 27].filter { $0 != calendar.component(.day, from: now) }.map { day in
            let date = calendar.date(byAdding: .day, value: day - 1, to: month)!
            return event("day-\(day)", "Calendar event \(day)", on: date, from: 14, to: 15)
        }
        fixture.reminders = [
            ReminderItem(id: "overdue", title: "Send notes", due: clock(on: priorDay, hour: 16), isCompleted: false),
            ReminderItem(id: "today", title: "Review checklist", due: clock(on: now, hour: 16), isCompleted: false),
        ]
        if full {
            fixture.events += (13...15).map { hour in
                event("extra-\(hour)", "Fixture event \(hour)", on: now, from: hour, to: hour + 1)
            }
        }
    }

    private func event(_ id: String, _ title: String, on day: Date,
                       from start: Int, minute: Int = 0, to end: Int) -> CalendarEvent {
        CalendarEvent(id: id, title: title, start: clock(on: day, hour: start, minute: minute),
                      end: clock(on: day, hour: end), isAllDay: false, colorRGB: [0.78, 0.42, 0.88])
    }
}
