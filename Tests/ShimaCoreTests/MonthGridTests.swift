import Foundation
import ShimaCore
import Testing

struct MonthGridTests {
    @Test func octoberTwentyTwentySix() {
        let calendar = calendarFixture()
        let today = calendarDate(calendar, 10, 4)
        let grid = MonthGrid.make(month: calendarDate(calendar, 10, 15), today: today, calendar: calendar)

        #expect(grid.weeks.count == 5)
        #expect(grid.weeks.allSatisfy { $0.count == 7 })
        #expect(grid.weeks[0][0].date == calendarDate(calendar, 9, 27))
        #expect(!grid.weeks[0][0].inMonth)
        #expect(grid.weeks[0][4].date == calendarDate(calendar, 10, 1))
        #expect(grid.weeks[0][4].inMonth)
        #expect(grid.weeks[4][6].date == calendarDate(calendar, 10, 31))
        #expect(grid.weeks.flatMap { $0 }.filter(\.isToday).map(\.date) == [today])
        #expect(grid.title == "OCTOBER 2026")
        #expect(grid.weekdaySymbols.count == 7)
        #expect(grid.visibleRange.start == calendarDate(calendar, 9, 27))
        #expect(grid.visibleRange.end == calendarDate(calendar, 11, 1))
    }

    @Test func sixWeekMonth() {
        let calendar = calendarFixture()
        let may = calendarDate(calendar, 5, 1)
        let february = calendarDate(calendar, 2, 1)
        #expect(MonthGrid.make(month: may, today: may, calendar: calendar).weeks.count == 6)
        #expect(MonthGrid.make(month: february, today: may, calendar: calendar).weeks.count == 4)
    }

    @Test func mondayFirstGrid() {
        var calendar = calendarFixture()
        calendar.firstWeekday = 2
        let october = calendarDate(calendar, 10, 1)
        let grid = MonthGrid.make(month: october, today: october, calendar: calendar)

        #expect(grid.weeks[0][0].date == calendarDate(calendar, 9, 28))
        #expect(grid.weekdaySymbols.first == calendar.veryShortStandaloneWeekdaySymbols[1])
        #expect(grid.weekdaySymbols.last == calendar.veryShortStandaloneWeekdaySymbols[0])
    }

    @Test func dstSafeDays() {
        var calendar = calendarFixture()
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let november = calendarDate(calendar, 11, 1)
        let grid = MonthGrid.make(month: november, today: november, calendar: calendar)
        let days = grid.weeks.flatMap { $0 }

        for (day, nextDay) in zip(days, days.dropFirst()) {
            #expect(calendar.date(byAdding: .day, value: 1, to: day.date) == nextDay.date)
            #expect(calendar.startOfDay(for: nextDay.date) == nextDay.date)
        }
        #expect(days.filter(\.inMonth).map(\.dayNumber) == Array(1...30))
        #expect(grid.visibleRange.end == calendarDate(calendar, 12, 6))
    }
}

func calendarFixture() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    return calendar
}

func calendarDate(_ calendar: Calendar, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}
