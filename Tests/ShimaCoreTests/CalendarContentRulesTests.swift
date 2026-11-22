import Foundation
import ShimaCore
import Testing

struct CalendarContentRulesTests {
    private let calendar = calendarFixture()

    @Test func allDayEventEndExclusive() {
        let fifth = date(5)
        let sixth = date(6)
        let event = event("all-day", fifth, sixth, allDay: true)
        let grid = MonthGrid.make(month: fifth, today: fifth, calendar: calendar)

        #expect(CalendarContentRules.events([event], on: fifth, calendar: calendar) == [event])
        #expect(CalendarContentRules.events([event], on: sixth, calendar: calendar).isEmpty)
        #expect(CalendarContentRules.dotDays(events: [event], in: grid, calendar: calendar) == [fifth])
    }

    @Test func multiDayEventDotsEveryDay() {
        let fifth = date(5)
        let event = event("multi-day", date(5, 22), date(7, 1))
        let grid = MonthGrid.make(month: fifth, today: fifth, calendar: calendar)

        #expect(CalendarContentRules.dotDays(events: [event], in: grid, calendar: calendar) == [
            fifth, date(6), date(7)
        ])
    }

    @Test func leftColumnOrdersAndCaps() {
        let running = event("running", date(4, 19), date(4, 20))
        let upcoming1 = event("upcoming1", date(4, 20), date(4, 21))
        let upcoming2 = event("upcoming2", date(4, 21), date(4, 22))
        let allDay = event("all-day", date(4), date(5), allDay: true)
        let past = event("past", date(4, 18), date(4, 19))
        let overdue = reminder("Overdue", date(3))
        let today = reminder("Due today", date(4, 21))
        let now = date(4, 19, 30)
        let events = [upcoming2, past, upcoming1, allDay, running]
        let reminders = [today, overdue]
        let full = CalendarContentRules.leftColumn(
            events: events, reminders: reminders, selectedDay: date(4), now: now, calendar: calendar
        )

        #expect(full.rows == [
            .event(running, .running), .event(upcoming1, .upcoming), .event(upcoming2, .upcoming),
            .event(allDay, .allDay)
        ])
        #expect(full.overflow == 3)

        let uncapped = CalendarContentRules.leftColumn(
            events: [running], reminders: reminders, selectedDay: date(4), now: now, calendar: calendar
        )
        #expect(uncapped.rows == [
            .event(running, .running), .reminder(overdue, overdue: true), .reminder(today, overdue: false)
        ])
        #expect(uncapped.overflow == 0)

        let pastOnly = CalendarContentRules.leftColumn(
            events: [past], reminders: reminders, selectedDay: date(4), now: now, calendar: calendar
        )
        #expect(pastOnly.rows == [
            .event(past, .past), .reminder(overdue, overdue: true), .reminder(today, overdue: false)
        ])
    }

    @Test func noRemindersOnOtherDays() {
        let column = CalendarContentRules.leftColumn(
            events: [], reminders: [reminder("Today", date(4)), reminder("Selected", date(5))],
            selectedDay: date(5), now: date(4, 19, 30), calendar: calendar
        )
        #expect(column.rows.isEmpty)
        #expect(column.overflow == 0)
    }

    @Test func onlyIncompleteRemindersDueTodayOrEarlierAppear() {
        let earlier = reminder("Earlier", date(2))
        let overdue = reminder("Overdue", date(3))
        let alpha = reminder("Alpha", date(4, 8))
        let bravo = reminder("Bravo", date(4, 8))
        let future = reminder("Tomorrow", date(5))
        let undated = reminder("Undated", nil)
        let complete = reminder("Completed", date(3), completed: true)
        let column = CalendarContentRules.leftColumn(
            events: [], reminders: [future, bravo, overdue, undated, complete, alpha, earlier],
            selectedDay: date(4), now: date(4, 19, 30), calendar: calendar
        )

        #expect(column.rows == [
            .reminder(earlier, overdue: true), .reminder(overdue, overdue: true),
            .reminder(alpha, overdue: false), .reminder(bravo, overdue: false)
        ])
        #expect(column.overflow == 0)
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendarDate(calendar, 10, day, hour, minute)
    }

    private func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, title: id, start: start, end: end, isAllDay: allDay, colorRGB: [0, 0, 0])
    }

    private func reminder(_ title: String, _ due: Date?, completed: Bool = false) -> ReminderItem {
        ReminderItem(id: title, title: title, due: due, isCompleted: completed)
    }
}
