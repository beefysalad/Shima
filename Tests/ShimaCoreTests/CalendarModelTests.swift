import Foundation
import Testing
@testable import ShimaCore

struct CalendarModelTests {
    private let calendar = calendarTestCalendar()
    private let now = calendarTestDate(2026, 10, 25)

    @Test func hoverNeverRequestsOrLoads() {
        var model = CalendarModel(calendar: calendar, now: now)
        #expect(model.setContext(mode: .expanded, tab: .music, screenAvailable: true, now: now).isEmpty)
        #expect(!model.isVisible)
    }

    @Test func openingRequestsEventsThenReminders() {
        var model = CalendarModel(calendar: calendar, now: now)
        #expect(open(&model) == [.requestEventsAccess])
        #expect(model.setAccess(events: .authorized, reminders: .notDetermined, now: now)
                == [.requestRemindersAccess, .load(range(for: now))])
        #expect(model.setAccess(events: .authorized, reminders: .notDetermined, now: now).isEmpty)
    }

    @Test func loadsOnceThenOnlyWhenStale() {
        var model = authorizedModel()
        let expected: [CalendarEffect] = [.load(range(for: now))]
        #expect(open(&model) == expected)
        model.dataLoaded(events: [], reminders: [], range: range(for: now))
        #expect(open(&model).isEmpty)
        #expect(model.markStale() == expected)
        model.dataLoaded(events: [], reminders: [], range: range(for: now))
        #expect(close(&model).isEmpty)
        #expect(open(&model).isEmpty)
        #expect(close(&model).isEmpty)
        #expect(model.markStale().isEmpty)
        #expect(open(&model) == expected)
    }

    @Test func monthArrowsReloadRange() {
        var model = authorizedModel()
        _ = open(&model)
        let november = calendarTestDate(2026, 11, 1)
        #expect(model.showMonth(offset: 1) == [.load(range(for: november))])
        #expect(model.displayedMonth == november)
    }

    @Test func reopenResetsSelection() {
        var model = authorizedModel()
        _ = open(&model)
        _ = model.showMonth(offset: 1)
        model.selectDay(calendarTestDate(2026, 11, 15))
        _ = close(&model)
        _ = open(&model)
        #expect(model.displayedMonth == calendarTestDate(2026, 10, 1))
        #expect(model.selectedDay == now)
    }

    @Test func goToTodayRestoresCurrentMonthAndDay() {
        var model = authorizedModel()
        _ = open(&model)
        _ = model.showMonth(offset: 1)
        model.selectDay(calendarTestDate(2026, 11, 15))
        #expect(model.goToToday(now: now) == [.load(range(for: now))])
        #expect(model.displayedMonth == calendarTestDate(2026, 10, 1))
        #expect(model.selectedDay == now)
    }

    @Test func collapseWhileHiddenNeverLoads() {
        var model = authorizedModel()
        #expect(close(&model).isEmpty)
        #expect(model.setContext(mode: .expanded, tab: .calendar, screenAvailable: false, now: now).isEmpty)
        #expect(model.showMonth(offset: 1).isEmpty)
        #expect(model.dayChanged(now: calendarTestDate(2026, 10, 26)).isEmpty)
    }

    @Test func dayChangedUpdatesTodayAndLoadsWhenVisible() {
        var model = CalendarModel(calendar: calendar, now: calendarTestDate(2026, 10, 31), eventsAccess: .authorized, remindersAccess: .authorized)
        _ = model.setContext(mode: .expanded, tab: .calendar, screenAvailable: true, now: calendarTestDate(2026, 10, 31))
        let tomorrow = calendarTestDate(2026, 11, 1)
        #expect(model.dayChanged(now: tomorrow) == [.load(range(for: tomorrow))])
        #expect(model.selectedDay == tomorrow)
        #expect(model.displayedMonth == tomorrow)
    }

    @Test func revokedAccessClearsData() {
        var model = authorizedModel()
        _ = open(&model)
        let event = CalendarEvent(id: "event", title: "Event", start: now, end: now.addingTimeInterval(60), isAllDay: false, colorRGB: [1, 0, 0])
        model.dataLoaded(events: [event], reminders: [calendarTestReminder("keep")], range: range(for: now))
        #expect(model.events == [event])
        #expect(model.setAccess(events: .denied, reminders: .authorized, now: now) == [.load(range(for: now))])
        #expect(model.events.isEmpty)
        #expect(model.reminders == [calendarTestReminder("keep")])
    }

    @Test func completeRemovesLocallyAndEmitsEffect() {
        var model = modelWithReminder()
        #expect(model.completeReminder(id: "complete") == [.completeReminder("complete")])
        #expect(model.reminders.isEmpty)
        #expect(model.completeReminder(id: "complete").isEmpty)
    }

    @Test func completionFailedRestoresItem() {
        var model = modelWithReminder()
        let reminder = calendarTestReminder("complete")
        _ = model.completeReminder(id: reminder.id)
        model.completionFailed(reminder)
        model.completionFailed(reminder)
        #expect(model.reminders == [reminder])
    }

    @Test func shutdownStopsEverything() {
        var model = modelWithReminder()
        #expect(model.shutdown().isEmpty)
        #expect(!model.isVisible)
        #expect(model.events.isEmpty && model.reminders.isEmpty)
        #expect(open(&model).isEmpty)
        #expect(model.setAccess(events: .authorized, reminders: .authorized, now: now).isEmpty)
        #expect(model.markStale().isEmpty)
        #expect(model.completeReminder(id: "complete").isEmpty)
        model.dataLoaded(events: [], reminders: [calendarTestReminder("late")], range: range(for: now))
        #expect(model.reminders.isEmpty)
    }

    private func authorizedModel() -> CalendarModel {
        CalendarModel(calendar: calendar, now: now, eventsAccess: .authorized, remindersAccess: .authorized)
    }

    private func modelWithReminder() -> CalendarModel {
        var model = authorizedModel()
        _ = open(&model)
        model.dataLoaded(events: [], reminders: [calendarTestReminder("complete")], range: range(for: now))
        return model
    }

    private func range(for month: Date) -> DateInterval {
        MonthGrid.make(month: month, today: now, calendar: calendar).visibleRange
    }

    private func open(_ model: inout CalendarModel) -> [CalendarEffect] {
        model.setContext(mode: .expanded, tab: .calendar, screenAvailable: true, now: now)
    }

    private func close(_ model: inout CalendarModel) -> [CalendarEffect] {
        model.setContext(mode: .collapsed, tab: .music, screenAvailable: true, now: now)
    }
}

func calendarTestCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 1
    return calendar
}

func calendarTestDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendarTestCalendar().date(from: DateComponents(year: year, month: month, day: day))!
}

func calendarTestReminder(_ id: String) -> ReminderItem {
    ReminderItem(id: id, title: id, due: nil, isCompleted: false)
}
