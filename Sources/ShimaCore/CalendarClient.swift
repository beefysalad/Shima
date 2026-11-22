import Foundation

@MainActor public protocol CalendarClient: AnyObject {
    var eventsAccess: CalendarAccess { get }
    var remindersAccess: CalendarAccess { get }

    func requestEventsAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void)
    func requestRemindersAccess(_ completion: @escaping @MainActor (CalendarAccess) -> Void)
    func events(in range: DateInterval) -> [CalendarEvent]
    func loadReminders(_ completion: @escaping @MainActor ([ReminderItem]) -> Void)
    func complete(reminderID: String) -> Bool

    var onStoreChanged: (@MainActor () -> Void)? { get set }
    var onDayChanged: (@MainActor () -> Void)? { get set }
}
