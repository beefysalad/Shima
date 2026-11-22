import Foundation

public struct CalendarEvent: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    /// Red, green and blue components in the range 0...1.
    public let colorRGB: [Double]

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, colorRGB: [Double]) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.colorRGB = colorRGB
    }

    public var displayTitle: String { calendarDisplayTitle(title) }
}

public struct ReminderItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let due: Date?
    public let isCompleted: Bool

    public init(id: String, title: String, due: Date?, isCompleted: Bool) {
        self.id = id
        self.title = title
        self.due = due
        self.isCompleted = isCompleted
    }

    public var displayTitle: String { calendarDisplayTitle(title) }
}

public enum CalendarAccess: Equatable, Sendable {
    case notDetermined, authorized, denied
}

private func calendarDisplayTitle(_ title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "(No title)" : trimmed
}
