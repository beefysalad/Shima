import Foundation

public enum EventPhase: Int, Equatable, Sendable {
    case running, upcoming, allDay, past
}

public enum LeftRow: Equatable, Sendable {
    case event(CalendarEvent, EventPhase)
    case reminder(ReminderItem, overdue: Bool)
}

public struct LeftColumn: Equatable, Sendable {
    public let rows: [LeftRow]
    public let overflow: Int
}

public enum CalendarContentRules {
    public static func events(_ events: [CalendarEvent], on day: Date, calendar: Calendar) -> [CalendarEvent] {
        let dayRange = calendar.dateInterval(of: .day, for: day)!
        return events.filter { overlaps($0, dayRange) }
    }

    public static func dotDays(events: [CalendarEvent], in grid: MonthGridModel, calendar: Calendar) -> Set<Date> {
        var days: Set<Date> = []
        for day in grid.weeks.joined() {
            let dayRange = calendar.dateInterval(of: .day, for: day.date)!
            if events.contains(where: { overlaps($0, dayRange) }) {
                days.insert(dayRange.start)
            }
        }
        return days
    }

    public static func leftColumn(
        events: [CalendarEvent],
        reminders: [ReminderItem],
        selectedDay: Date,
        now: Date,
        calendar: Calendar,
        cap: Int = 4
    ) -> LeftColumn {
        let dayRange = calendar.dateInterval(of: .day, for: selectedDay)!
        var rows: [LeftRow] = events
            .filter { overlaps($0, dayRange) }
            .map { (event: $0, phase: phase(for: $0, now: now)) }
            .sorted { ($0.phase.rawValue, $0.event.start) < ($1.phase.rawValue, $1.event.start) }
            .map { .event($0.event, $0.phase) }

        if now >= dayRange.start && now < dayRange.end {
            let dueReminders = reminders.compactMap { reminder -> (item: ReminderItem, due: Date)? in
                guard !reminder.isCompleted, let due = reminder.due, due < dayRange.end else { return nil }
                return (reminder, due)
            }
            rows += dueReminders
                .sorted { ($0.due, $0.item.title) < ($1.due, $1.item.title) }
                .map { .reminder($0.item, overdue: $0.due < dayRange.start) }
        }

        let visibleCount = min(rows.count, max(0, cap))
        return LeftColumn(rows: Array(rows.prefix(visibleCount)), overflow: rows.count - visibleCount)
    }

    private static func overlaps(_ event: CalendarEvent, _ day: DateInterval) -> Bool {
        event.start < event.end && event.start < day.end && event.end > day.start
    }

    private static func phase(for event: CalendarEvent, now: Date) -> EventPhase {
        if event.isAllDay { return .allDay }
        if now < event.start { return .upcoming }
        if now < event.end { return .running }
        return .past
    }
}
