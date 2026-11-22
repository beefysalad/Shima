import CoreGraphics
import EventKit
import Foundation
import ShimaCore

@MainActor final class EventKitCalendarClient: CalendarClient {
    var onStoreChanged: (@MainActor () -> Void)?
    var onDayChanged: (@MainActor () -> Void)?

    private lazy var store = EKEventStore()
    private var storeObserver: NSObjectProtocol?
    private var dayObserver: NSObjectProtocol?

    init() {
        dayObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.onDayChanged?() }
        }
    }

    var eventsAccess: CalendarAccess { Self.access(for: .event) }
    var remindersAccess: CalendarAccess { Self.access(for: .reminder) }

    private static func access(for entity: EKEntityType) -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: entity) {
        case .fullAccess: .authorized
        case .notDetermined: .notDetermined
        case .denied, .restricted, .writeOnly: .denied
        @unknown default: .denied
        }
    }

    func requestEventsAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void) {
        observedStore.requestFullAccessToEvents { @Sendable _, error in
            if let error { Log.calendar.error("calendar access request failed: \(error.localizedDescription)") }
            Task { @MainActor in completion(Self.access(for: .event)) }
        }
    }

    func requestRemindersAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void) {
        observedStore.requestFullAccessToReminders { @Sendable _, error in
            if let error { Log.calendar.error("reminders access request failed: \(error.localizedDescription)") }
            Task { @MainActor in completion(Self.access(for: .reminder)) }
        }
    }

    func events(in range: DateInterval) -> [CalendarEvent] {
        guard eventsAccess == .authorized else { return [] }
        let store = observedStore
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        Log.calendar.debug("calendar loading events")
        return store.events(matching: predicate).compactMap { event in
            guard let id = event.eventIdentifier, let start = event.startDate, let end = event.endDate else { return nil }
            // Recurrences can share an EventKit identifier. Include the occurrence date.
            let occurrence = event.occurrenceDate ?? start
            return CalendarEvent(
                id: "\(id):\(occurrence.timeIntervalSinceReferenceDate)",
                title: event.title ?? "", start: start, end: end, isAllDay: event.isAllDay,
                colorRGB: Self.rgbComponents(of: event.calendar.cgColor))
        }
    }

    func loadReminders(_ completion: @escaping @MainActor ([ReminderItem]) -> Void) {
        guard remindersAccess == .authorized,
              let today = Calendar.autoupdatingCurrent.dateInterval(of: .day, for: Date()) else {
            completion([])
            return
        }
        let store = observedStore
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: today.end, calendars: nil)
        let timeZone = TimeZone.current
        Log.calendar.debug("calendar loading due reminders")
        _ = store.fetchReminders(matching: predicate) { @Sendable reminders in
            // Read EventKit objects on the callback queue and send only value types.
            let items: [ReminderItem] = (reminders ?? []).compactMap { reminder in
                guard !reminder.isCompleted,
                      var components = reminder.dueDateComponents else { return nil }
                var calendar = components.calendar ?? Calendar(identifier: .gregorian)
                // Floating due dates use the local time zone, including all-day reminders.
                calendar.timeZone = components.timeZone ?? timeZone
                components.calendar = nil
                components.timeZone = calendar.timeZone
                guard let due = calendar.date(from: components), due < today.end else { return nil }
                return ReminderItem(id: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                                    due: due, isCompleted: false)
            }
            Task { @MainActor in completion(items) }
        }
    }

    func complete(reminderID: String) -> Bool {
        guard remindersAccess == .authorized else { return false }
        let store = observedStore
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            Log.calendar.error("calendar could not find reminder to complete")
            return false
        }
        if reminder.isCompleted { return true }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            Log.calendar.debug("calendar completed reminder")
            return true
        } catch {
            reminder.isCompleted = false
            Log.calendar.error("calendar reminder completion failed: \(error.localizedDescription)")
            return false
        }
    }

    func shutdown() {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
            self.storeObserver = nil
        }
        if let dayObserver {
            NotificationCenter.default.removeObserver(dayObserver)
            self.dayObserver = nil
        }
        onStoreChanged = nil
        onDayChanged = nil
    }

    private var observedStore: EKEventStore {
        if storeObserver == nil {
            storeObserver = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: nil
            ) { [weak self] _ in
                Task { @MainActor in self?.onStoreChanged?() }
            }
        }
        return store
    }

    private static func rgbComponents(of color: CGColor?) -> [Double] {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let components = color?.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else { return [0.5, 0.5, 0.5] }
        return components.prefix(3).map { min(1, max(0, Double($0))) }
    }
}
