import Foundation

public enum CalendarEffect: Equatable, Sendable {
    case requestEventsAccess
    case requestRemindersAccess
    case load(DateInterval)
    case completeReminder(String)
}

public struct CalendarModel: Equatable, Sendable {
    public private(set) var eventsAccess: CalendarAccess
    public private(set) var remindersAccess: CalendarAccess
    public private(set) var displayedMonth: Date
    public private(set) var selectedDay: Date
    public private(set) var events: [CalendarEvent] = []
    public private(set) var reminders: [ReminderItem] = []
    public private(set) var isVisible = false

    private let calendar: Calendar
    private var today: Date
    private var eventsRequested = false
    private var remindersRequested = false
    private var terminated = false
    private var needsLoad = true
    private var loadedRange: DateInterval?
    private var pendingRange: DateInterval?
    // A store notification may report new access before the prompt callback arrives.
    var eventsRequestInFlight = false

    public init(calendar: Calendar, now: Date, eventsAccess: CalendarAccess = .notDetermined,
                remindersAccess: CalendarAccess = .notDetermined) {
        self.calendar = calendar
        self.eventsAccess = eventsAccess
        self.remindersAccess = remindersAccess
        today = calendar.startOfDay(for: now)
        selectedDay = today
        displayedMonth = calendar.dateInterval(of: .month, for: now)?.start ?? today
    }

    public mutating func setContext(mode: IslandMode, tab: IslandTab, screenAvailable: Bool, now: Date) -> [CalendarEffect] {
        guard !terminated else { return [] }
        let visible = mode == .expanded && tab == .calendar && screenAvailable
        if visible && !isVisible {
            resetToToday(now)
        }
        if !visible && pendingRange != nil {
            pendingRange = nil
            needsLoad = true
        }
        isVisible = visible
        return reconcile()
    }

    public mutating func setAccess(events: CalendarAccess, reminders: CalendarAccess, now: Date) -> [CalendarEffect] {
        guard !terminated else { return [] }
        updateAccess(events: events, reminders: reminders)
        return reconcile()
    }

    @discardableResult
    mutating func updateAccess(events: CalendarAccess, reminders: CalendarAccess) -> Bool {
        guard !terminated, eventsAccess != events || remindersAccess != reminders else { return false }
        eventsAccess = events
        remindersAccess = reminders
        if eventsAccess != .authorized { self.events = [] }
        if remindersAccess != .authorized { self.reminders = [] }
        pendingRange = nil
        needsLoad = true
        return true
    }

    public mutating func dataLoaded(events: [CalendarEvent], reminders: [ReminderItem], range: DateInterval) {
        guard isVisible, pendingRange == range else { return }
        self.events = eventsAccess == .authorized ? events : []
        self.reminders = remindersAccess == .authorized ? reminders : []
        loadedRange = range
        pendingRange = nil
    }

    public mutating func markStale() -> [CalendarEffect] {
        guard !terminated else { return [] }
        needsLoad = true
        return reconcile()
    }

    public mutating func dayChanged(now: Date) -> [CalendarEffect] {
        guard !terminated else { return [] }
        let previousToday = today
        today = calendar.startOfDay(for: now)
        if selectedDay == previousToday {
            selectedDay = today
            if calendar.isDate(displayedMonth, equalTo: previousToday, toGranularity: .month) {
                displayedMonth = monthStart(for: today)
            }
        }
        return markStale()
    }

    public mutating func selectDay(_ day: Date) {
        guard isVisible else { return }
        selectedDay = calendar.startOfDay(for: day)
    }

    public mutating func showMonth(offset: Int) -> [CalendarEffect] {
        guard isVisible, offset != 0,
              let month = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return [] }
        displayedMonth = monthStart(for: month)
        return reconcile()
    }

    public mutating func goToToday(now: Date) -> [CalendarEffect] {
        guard isVisible else { return [] }
        resetToToday(now)
        return reconcile()
    }

    public mutating func completeReminder(id: String) -> [CalendarEffect] {
        guard isVisible, remindersAccess == .authorized, reminders.contains(where: { $0.id == id }) else { return [] }
        reminders.removeAll { $0.id == id }
        return [.completeReminder(id)]
    }

    public mutating func completionFailed(_ item: ReminderItem) {
        guard !terminated, remindersAccess == .authorized, !reminders.contains(where: { $0.id == item.id }) else { return }
        reminders.append(item)
    }

    public mutating func shutdown() -> [CalendarEffect] {
        terminated = true
        isVisible = false
        pendingRange = nil
        events = []
        reminders = []
        return []
    }

    private mutating func resetToToday(_ now: Date) {
        today = calendar.startOfDay(for: now)
        selectedDay = today
        displayedMonth = monthStart(for: today)
    }

    private func monthStart(for day: Date) -> Date {
        calendar.dateInterval(of: .month, for: day)?.start ?? day
    }

    private mutating func reconcile() -> [CalendarEffect] {
        guard isVisible else { return [] }
        var effects: [CalendarEffect] = []
        if eventsAccess == .notDetermined && !eventsRequested {
            eventsRequested = true
            effects.append(.requestEventsAccess)
        } else if eventsAccess != .notDetermined && !eventsRequestInFlight &&
                    remindersAccess == .notDetermined && !remindersRequested {
            remindersRequested = true
            effects.append(.requestRemindersAccess)
        }

        if eventsAccess == .authorized || remindersAccess == .authorized {
            let range = MonthGrid.make(month: displayedMonth, today: today, calendar: calendar).visibleRange
            if needsLoad || (pendingRange ?? loadedRange) != range {
                needsLoad = false
                pendingRange = range
                effects.append(.load(range))
            }
        }
        return effects
    }
}
