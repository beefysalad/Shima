import Foundation

public struct GridDay: Equatable, Sendable {
    public let date: Date
    public let dayNumber: Int
    public let inMonth: Bool
    public let isToday: Bool
}

public struct MonthGridModel: Equatable, Sendable {
    public let title: String
    public let weekdaySymbols: [String]
    public let weeks: [[GridDay]]
    public let visibleRange: DateInterval
}

public enum MonthGrid {
    public static func make(month: Date, today: Date, calendar: Calendar) -> MonthGridModel {
        let monthRange = calendar.dateInterval(of: .month, for: month)!
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let weekLength = symbols.count
        let firstWeekday = calendar.firstWeekday
        let weekdaySymbols = Array(symbols[(firstWeekday - 1)...]) + Array(symbols.prefix(firstWeekday - 1))
        let monthStartWeekday = calendar.component(.weekday, from: monthRange.start)
        let leadingDays = (monthStartWeekday - firstWeekday + weekLength) % weekLength
        let firstDay = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -leadingDays, to: monthRange.start)!
        )
        let todayStart = calendar.startOfDay(for: today)

        var cursor = firstDay
        var weeks: [[GridDay]] = []
        while cursor < monthRange.end {
            var week: [GridDay] = []
            for _ in 0..<weekLength {
                week.append(GridDay(
                    date: cursor,
                    dayNumber: calendar.component(.day, from: cursor),
                    inMonth: cursor >= monthRange.start && cursor < monthRange.end,
                    isToday: cursor == todayStart
                ))
                cursor = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: cursor)!)
            }
            weeks.append(week)
        }

        let locale = calendar.locale ?? .current
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return MonthGridModel(
            title: formatter.string(from: month).uppercased(with: locale),
            weekdaySymbols: weekdaySymbols,
            weeks: weeks,
            visibleRange: DateInterval(start: firstDay, end: cursor)
        )
    }
}
