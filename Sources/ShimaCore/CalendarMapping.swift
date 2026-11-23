import Foundation

/// Value mapping shared by the EventKit adapter and fixtures, without store access.
public enum CalendarMapping {
    /// EKAuthorizationStatus's stable raw values: notDetermined = 0, fullAccess = 3.
    /// Restricted, denied, writeOnly and future statuses cannot read calendar data.
    public static func access(authorizationStatus: Int) -> CalendarAccess {
        switch authorizationStatus {
        case 0: .notDetermined
        case 3: .authorized
        default: .denied
        }
    }

    /// Components have already been converted to sRGB by the platform adapter.
    public static func rgbComponents(_ components: [Double]?) -> [Double] {
        guard let components, components.count >= 3 else { return [0.5, 0.5, 0.5] }
        return components.prefix(3).map { min(1, max(0, $0)) }
    }

    public static func event(id: String?, title: String?, start: Date?, end: Date?, occurrence: Date?,
                             isAllDay: Bool, colorRGB: [Double]) -> CalendarEvent? {
        guard let id, let start, let end else { return nil }
        // Recurrences can share an EventKit identifier. Include the occurrence date.
        let occurrence = occurrence ?? start
        return CalendarEvent(id: "\(id):\(occurrence.timeIntervalSinceReferenceDate)", title: title ?? "",
                             start: start, end: end, isAllDay: isAllDay, colorRGB: colorRGB)
    }

    public static func reminder(id: String, title: String?, components: DateComponents?, isCompleted: Bool,
                                before end: Date, timeZone: TimeZone) -> ReminderItem? {
        guard !isCompleted, var components else { return nil }
        var calendar = components.calendar ?? Calendar(identifier: .gregorian)
        // Floating due dates use the local time zone, including all-day reminders.
        calendar.timeZone = components.timeZone ?? timeZone
        components.calendar = nil
        components.timeZone = calendar.timeZone
        guard let due = calendar.date(from: components), due < end else { return nil }
        return ReminderItem(id: id, title: title ?? "", due: due, isCompleted: false)
    }
}
