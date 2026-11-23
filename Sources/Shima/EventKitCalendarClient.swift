import CoreGraphics
import EventKit
import Foundation
import ShimaCore

/// The mapping reads these properties only; fixtures never need an EventKit store.
protocol CalendarEventRecord {
    var eventID: String? { get }
    var eventStart: Date? { get }
    var eventEnd: Date? { get }
    var eventOccurrence: Date? { get }
    var itemTitle: String? { get }
    var isAllDay: Bool { get }
    var calendarColor: CGColor? { get }
}

extension EKEvent: CalendarEventRecord {
    var eventID: String? { eventIdentifier }
    var eventStart: Date? { startDate }
    var eventEnd: Date? { endDate }
    var eventOccurrence: Date? { occurrenceDate }
    var itemTitle: String? { title }
    var calendarColor: CGColor? { calendar?.cgColor }
}

protocol CalendarReminderRecord {
    var calendarItemIdentifier: String { get }
    var itemTitle: String? { get }
    var dueDateComponents: DateComponents? { get }
    var isCompleted: Bool { get }
}

extension EKReminder: CalendarReminderRecord { var itemTitle: String? { title } }

@MainActor final class EventKitCalendarClient: CalendarClient {
    var onStoreChanged: (@MainActor () -> Void)?
    var onDayChanged: (@MainActor () -> Void)?

    private lazy var store = EKEventStore()
    private var storeObserver: NSObjectProtocol?
    private var dayObserver: NSObjectProtocol?

    private let authorization: @MainActor (EKEntityType) -> EKAuthorizationStatus
    private let readEvents: (@MainActor (DateInterval) -> [any CalendarEventRecord])?
    private let readReminders: (@MainActor (Date, @escaping @Sendable ([any CalendarReminderRecord]?) -> Void) -> Void)?
    private let now: @MainActor () -> Date
    private let calendar: @MainActor () -> Calendar
    private let timeZone: @MainActor () -> TimeZone

    init(authorization: @escaping @MainActor (EKEntityType) -> EKAuthorizationStatus = { EKEventStore.authorizationStatus(for: $0) },
         readEvents: (@MainActor (DateInterval) -> [any CalendarEventRecord])? = nil,
         readReminders: (@MainActor (Date, @escaping @Sendable ([any CalendarReminderRecord]?) -> Void) -> Void)? = nil,
         now: @escaping @MainActor () -> Date = { Date() },
         calendar: @escaping @MainActor () -> Calendar = { .autoupdatingCurrent },
         timeZone: @escaping @MainActor () -> TimeZone = { .current }) {
        self.authorization = authorization
        self.readEvents = readEvents
        self.readReminders = readReminders
        self.now = now
        self.calendar = calendar
        self.timeZone = timeZone
        dayObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.onDayChanged?() }
        }
    }

    var eventsAccess: CalendarAccess { access(for: .event) }
    var remindersAccess: CalendarAccess { access(for: .reminder) }

    private func access(for entity: EKEntityType) -> CalendarAccess {
        switch authorization(entity) {
        case .fullAccess: .authorized
        case .notDetermined: .notDetermined
        case .denied, .restricted, .writeOnly: .denied
        @unknown default: .denied
        }
    }

    func requestEventsAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void) {
        observedStore.requestFullAccessToEvents { @Sendable _, error in
            if let error { Log.calendar.error("calendar access request failed: \(error.localizedDescription)") }
            Task { @MainActor in completion(self.access(for: .event)) }
        }
    }

    func requestRemindersAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void) {
        observedStore.requestFullAccessToReminders { @Sendable _, error in
            if let error { Log.calendar.error("reminders access request failed: \(error.localizedDescription)") }
            Task { @MainActor in completion(self.access(for: .reminder)) }
        }
    }

    func events(in range: DateInterval) -> [CalendarEvent] {
        guard eventsAccess == .authorized else { return [] }
        let records: [any CalendarEventRecord]
        if let readEvents { records = readEvents(range) }
        else {
            let store = observedStore
            let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
            records = store.events(matching: predicate)
        }
        Log.calendar.debug("calendar loading events")
        return records.compactMap { event in
            guard let id = event.eventID, let start = event.eventStart, let end = event.eventEnd else { return nil }
            // Recurrences can share an EventKit identifier. Include the occurrence date.
            let occurrence = event.eventOccurrence ?? start
            return CalendarEvent(
                id: "\(id):\(occurrence.timeIntervalSinceReferenceDate)",
                title: event.itemTitle ?? "", start: start, end: end, isAllDay: event.isAllDay,
                colorRGB: Self.rgbComponents(of: event.calendarColor))
        }
    }

    func loadReminders(_ completion: @escaping @MainActor ([ReminderItem]) -> Void) {
        guard remindersAccess == .authorized,
              let today = calendar().dateInterval(of: .day, for: now()) else {
            completion([])
            return
        }
        let timeZone = timeZone()
        Log.calendar.debug("calendar loading due reminders")
        let receive: @Sendable ([any CalendarReminderRecord]?) -> Void = { reminders in
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
                return ReminderItem(id: reminder.calendarItemIdentifier, title: reminder.itemTitle ?? "",
                                    due: due, isCompleted: false)
            }
            Task { @MainActor in completion(items) }
        }
        if let readReminders { readReminders(today.end, receive) }
        else {
            let store = observedStore
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: today.end, calendars: nil)
            _ = store.fetchReminders(matching: predicate) { reminders in receive(reminders) }
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

    static func rgbComponents(of color: CGColor?) -> [Double] {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let components = color?.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else { return [0.5, 0.5, 0.5] }
        return components.prefix(3).map { min(1, max(0, Double($0))) }
    }
}
