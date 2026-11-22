import Foundation

@MainActor public final class FakeCalendarClient: CalendarClient {
    public var eventsAccess: CalendarAccess
    public var remindersAccess: CalendarAccess
    public var events: [CalendarEvent] = []
    public var reminders: [ReminderItem] = []
    public var requestResult: CalendarAccess?
    public var autoCompleteReminders = true
    public var completionResult = true
    public private(set) var eventsRequestCount = 0
    public private(set) var remindersRequestCount = 0
    public private(set) var eventsReadCount = 0
    public private(set) var loadCount = 0
    public private(set) var completedIDs: [String] = []

    public var onStoreChanged: (@MainActor () -> Void)?
    public var onDayChanged: (@MainActor () -> Void)?

    private enum Store { case events, reminders }
    private var pendingAccess: [(store: Store, completion: @MainActor (CalendarAccess) -> Void)] = []
    private var pendingReminders: [(items: [ReminderItem], completion: @MainActor ([ReminderItem]) -> Void)] = []

    public init(eventsAccess: CalendarAccess = .notDetermined, remindersAccess: CalendarAccess = .notDetermined,
                requestResult: CalendarAccess? = .authorized) {
        self.eventsAccess = eventsAccess
        self.remindersAccess = remindersAccess
        self.requestResult = requestResult
    }

    public func requestEventsAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void) {
        eventsRequestCount += 1
        requestAccess(for: .events, completion)
    }

    public func requestRemindersAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void) {
        remindersRequestCount += 1
        requestAccess(for: .reminders, completion)
    }

    public func completePendingAccess(_ result: CalendarAccess, at index: Int = 0) {
        guard pendingAccess.indices.contains(index) else { return }
        let request = pendingAccess.remove(at: index)
        switch request.store {
        case .events: eventsAccess = result
        case .reminders: remindersAccess = result
        }
        request.completion(result)
    }

    public func events(in range: DateInterval) -> [CalendarEvent] {
        eventsReadCount += 1
        return events.filter { $0.start < range.end && $0.end > range.start }
    }

    public func loadReminders(_ completion: @escaping @MainActor ([ReminderItem]) -> Void) {
        loadCount += 1
        let items = reminders.filter { !$0.isCompleted }
        if autoCompleteReminders {
            completion(items)
        } else {
            pendingReminders.append((items, completion))
        }
    }

    public func completePendingReminders(at index: Int = 0) {
        guard pendingReminders.indices.contains(index) else { return }
        let request = pendingReminders.remove(at: index)
        request.completion(request.items)
    }

    public func complete(reminderID: String) -> Bool {
        completedIDs.append(reminderID)
        if completionResult {
            reminders.removeAll { $0.id == reminderID }
        }
        return completionResult
    }

    private func requestAccess(for store: Store, _ completion: @escaping @MainActor (CalendarAccess) -> Void) {
        pendingAccess.append((store, completion))
        if let requestResult {
            completePendingAccess(requestResult, at: pendingAccess.count - 1)
        }
    }
}
