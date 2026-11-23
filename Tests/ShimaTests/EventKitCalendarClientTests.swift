import CoreGraphics
import EventKit
import Foundation
import Testing
@testable import Shima
@testable import ShimaCore

private struct EventFixture: CalendarEventRecord {
    var eventID: String? = "event"
    var eventStart: Date? = Date(timeIntervalSinceReferenceDate: 100)
    var eventEnd: Date? = Date(timeIntervalSinceReferenceDate: 200)
    var eventOccurrence: Date?
    var itemTitle: String? = "Meeting"
    var isAllDay = false
    var calendarColor: CGColor?
}

private struct ReminderFixture: CalendarReminderRecord {
    var calendarItemIdentifier = "reminder"
    var itemTitle: String? = "Due"
    var dueDateComponents: DateComponents?
    var isCompleted = false
}

@MainActor struct EventKitCalendarClientTests {
    private let start = Date(timeIntervalSinceReferenceDate: 100)
    private let end = Date(timeIntervalSinceReferenceDate: 200)
    private var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = utc; return c }

    @Test func authorizationStatusMapsWithoutReadingTheUsersStore() {
        for (status, expected) in [(EKAuthorizationStatus.fullAccess, CalendarAccess.authorized),
                                   (.notDetermined, .notDetermined), (.denied, .denied),
                                   (.restricted, .denied), (.writeOnly, .denied)] {
            var entities: [EKEntityType] = []
            let client = EventKitCalendarClient(authorization: { entities.append($0); return status })
            defer { client.shutdown() }
            #expect(client.eventsAccess == expected && client.remindersAccess == expected)
            #expect(entities == [.event, .reminder])
        }
    }

    @Test func eventMappingKeepsOccurrenceIdentityAndDropsIncompleteRecords() {
        let color = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0.25, 0.5, 0.75, 1])!
        let records: [EventFixture] = [
            EventFixture(eventOccurrence: Date(timeIntervalSinceReferenceDate: 300), itemTitle: nil, isAllDay: true, calendarColor: color),
            EventFixture(), EventFixture(eventID: nil), EventFixture(eventStart: nil), EventFixture(eventEnd: nil),
        ]
        var ranges: [DateInterval] = []
        let client = EventKitCalendarClient(authorization: { _ in .fullAccess }, readEvents: { range in
            ranges.append(range); return records
        })
        defer { client.shutdown() }
        let range = DateInterval(start: start, end: end)
        let events = client.events(in: range)
        #expect(ranges == [range])
        #expect(events == [CalendarEvent(id: "event:300.0", title: "", start: start, end: end,
                                        isAllDay: true, colorRGB: [0.25, 0.5, 0.75]),
                           CalendarEvent(id: "event:100.0", title: "Meeting", start: start, end: end,
                                         isAllDay: false, colorRGB: [0.5, 0.5, 0.5])])
    }

    @Test func deniedAccessNeverQueriesProviders() async {
        let client = EventKitCalendarClient(authorization: { _ in .denied },
            readEvents: { _ in Issue.record("Denied events must not query"); return [] },
            readReminders: { _, _ in Issue.record("Denied reminders must not query") })
        defer { client.shutdown() }
        #expect(client.events(in: DateInterval(start: start, end: end)).isEmpty)
        let reminders = await withCheckedContinuation { continuation in
            client.loadReminders { continuation.resume(returning: $0) }
        }
        #expect(reminders.isEmpty)
    }

    @Test func remindersMapFloatingDatesAndExcludeCompletedMissingAndTomorrow() async throws {
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))!
        let zone = TimeZone(secondsFromGMT: 8 * 3600)!
        let due = DateComponents(year: 2026, month: 11, day: 23, hour: 9)
        let records: [ReminderFixture] = [
            ReminderFixture(itemTitle: nil, dueDateComponents: due),
            ReminderFixture(calendarItemIdentifier: "explicit", dueDateComponents: DateComponents(timeZone: utc, year: 2026, month: 11, day: 23, hour: 9)),
            ReminderFixture(calendarItemIdentifier: "complete", dueDateComponents: due, isCompleted: true),
            ReminderFixture(calendarItemIdentifier: "missing"),
            ReminderFixture(calendarItemIdentifier: "tomorrow", dueDateComponents: DateComponents(timeZone: utc, year: 2026, month: 11, day: 24)),
        ]
        var ends: [Date] = []
        let client = EventKitCalendarClient(authorization: { _ in .fullAccess }, readReminders: { end, completion in
            ends.append(end); completion(records)
        }, now: { today }, calendar: { calendar }, timeZone: { zone })
        defer { client.shutdown() }
        let reminders = await withCheckedContinuation { continuation in
            client.loadReminders { continuation.resume(returning: $0) }
        }
        #expect(ends == [today.addingTimeInterval(86400)])
        #expect(reminders == [ReminderItem(id: "reminder", title: "", due: today.addingTimeInterval(3600), isCompleted: false),
                              ReminderItem(id: "explicit", title: "Due", due: today.addingTimeInterval(9 * 3600), isCompleted: false)])
    }

    @Test func rgbConversionHandlesMissingRGBAndGrayscaleColors() {
        #expect(EventKitCalendarClient.rgbComponents(of: nil) == [0.5, 0.5, 0.5])
        #expect(EventKitCalendarClient.rgbComponents(of: CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0.25, 0.5, 0.75, 1])!) == [0.25, 0.5, 0.75])
        for level: CGFloat in [0, 1] {
            let gray = EventKitCalendarClient.rgbComponents(of: CGColor(gray: level, alpha: 1))
            #expect(gray.count == 3 && gray.allSatisfy { abs($0 - Double(level)) < 0.001 })
        }
    }
}
