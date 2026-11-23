import Foundation
import Testing
@testable import ShimaCore

struct CalendarMappingTests {
    private let start = Date(timeIntervalSinceReferenceDate: 100)
    private let end = Date(timeIntervalSinceReferenceDate: 200)
    private var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = utc; return c }

    @Test func authorizationRawValuesAreReadOnlyUnlessFullAccessWasGranted() {
        #expect(CalendarMapping.access(authorizationStatus: 0) == .notDetermined)
        #expect(CalendarMapping.access(authorizationStatus: 3) == .authorized)
        for value in [1, 2, 4, -1, 5, Int.max] {
            #expect(CalendarMapping.access(authorizationStatus: value) == .denied)
        }
    }

    @Test func colorComponentsClampDropAlphaAndDefaultWhenMissing() {
        #expect(CalendarMapping.rgbComponents(nil) == [0.5, 0.5, 0.5])
        #expect(CalendarMapping.rgbComponents([]) == [0.5, 0.5, 0.5])
        #expect(CalendarMapping.rgbComponents([0.2, 1]) == [0.5, 0.5, 0.5])
        #expect(CalendarMapping.rgbComponents([-0.2, 0.3, 1.5, 0.7]) == [0, 0.3, 1])
        #expect(CalendarMapping.rgbComponents([0, 0.5, 1]) == [0, 0.5, 1])
    }

    @Test func eventsUseOccurrenceDatesAndRequireIdentifierStartAndEnd() {
        let occurrence = Date(timeIntervalSinceReferenceDate: 300)
        #expect(CalendarMapping.event(id: "repeated", title: nil, start: start, end: end, occurrence: occurrence,
                                      isAllDay: true, colorRGB: [1, 0, 0]) ==
                CalendarEvent(id: "repeated:300.0", title: "", start: start, end: end, isAllDay: true, colorRGB: [1, 0, 0]))
        #expect(CalendarMapping.event(id: "repeated", title: "One", start: start, end: end, occurrence: nil,
                                      isAllDay: false, colorRGB: [0, 1, 0]) ==
                CalendarEvent(id: "repeated:100.0", title: "One", start: start, end: end, isAllDay: false, colorRGB: [0, 1, 0]))
        for missing in 0..<3 {
            #expect(CalendarMapping.event(id: missing == 0 ? nil : "id", title: "", start: missing == 1 ? nil : start,
                                          end: missing == 2 ? nil : end, occurrence: nil, isAllDay: false, colorRGB: []) == nil)
        }
    }

    @Test func reminderDatesUseLocalZoneForFloatingAndExplicitZoneWhenPresent() throws {
        let local = TimeZone(secondsFromGMT: 8 * 3600)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))!
        let boundary = day.addingTimeInterval(86400)
        var components = DateComponents(year: 2026, month: 11, day: 23, hour: 9, minute: 30)
        let floating = try #require(CalendarMapping.reminder(id: "floating", title: nil, components: components,
                                                            isCompleted: false, before: boundary, timeZone: local))
        #expect(floating == ReminderItem(id: "floating", title: "", due: day.addingTimeInterval(5400), isCompleted: false))
        components.timeZone = utc
        let explicit = try #require(CalendarMapping.reminder(id: "zoned", title: "Call", components: components,
                                                            isCompleted: false, before: boundary, timeZone: local))
        #expect(explicit.due == day.addingTimeInterval(9.5 * 3600))
        components.hour = nil; components.minute = nil; components.timeZone = nil
        let allDay = try #require(CalendarMapping.reminder(id: "allDay", title: "All day", components: components,
                                                         isCompleted: false, before: boundary, timeZone: local))
        #expect(allDay.due == day.addingTimeInterval(-8 * 3600))
    }

    @Test func remindersKeepTheirCalendarButUseTheRequestedZoneForFloatingDates() throws {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(secondsFromGMT: -5 * 3600)!
        let components = DateComponents(calendar: buddhist, year: 2569, month: 11, day: 23, hour: 12)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12))!
        let item = try #require(CalendarMapping.reminder(id: "buddhist", title: "Lunch", components: components,
                                                       isCompleted: false, before: expected.addingTimeInterval(1), timeZone: utc))
        #expect(item.due == expected)
        #expect(components.calendar?.timeZone == buddhist.timeZone, "Mapping must not mutate the caller's components")
    }

    @Test func remindersExcludeCompletedMissingAndDatesAtOrAfterTheEndBoundary() {
        let due = DateComponents(timeZone: utc, year: 2026, month: 11, day: 23, hour: 12)
        let date = calendar.date(from: due)!
        #expect(CalendarMapping.reminder(id: "complete", title: "", components: due, isCompleted: true,
                                         before: date.addingTimeInterval(1), timeZone: utc) == nil)
        #expect(CalendarMapping.reminder(id: "missing", title: "", components: nil, isCompleted: false,
                                         before: date.addingTimeInterval(1), timeZone: utc) == nil)
        for boundary in [date, date.addingTimeInterval(-1)] {
            #expect(CalendarMapping.reminder(id: "late", title: "", components: due, isCompleted: false,
                                             before: boundary, timeZone: utc) == nil)
        }
        #expect(CalendarMapping.reminder(id: "overdue", title: "", components: due, isCompleted: false,
                                         before: date.addingTimeInterval(1), timeZone: utc)?.due == date)
    }
}
