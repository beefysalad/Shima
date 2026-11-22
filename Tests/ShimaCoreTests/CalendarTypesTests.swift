import Foundation
import ShimaCore
import Testing

struct CalendarTypesTests {
    @Test func emptyTitleFallback() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(1800)
        let unnamedEvent = CalendarEvent(
            id: "empty-event", title: "  ", start: start, end: end,
            isAllDay: false, colorRGB: [0, 0, 0]
        )
        let unnamedReminder = ReminderItem(
            id: "empty-reminder", title: "", due: nil, isCompleted: false
        )
        let standup = CalendarEvent(
            id: "standup", title: "Standup", start: start, end: end,
            isAllDay: false, colorRGB: [0, 0, 0]
        )
        let trimmedReminder = ReminderItem(
            id: "trimmed-reminder", title: " \nSend notes\t", due: nil, isCompleted: false
        )

        #expect(unnamedEvent.displayTitle == "(No title)")
        #expect(unnamedReminder.displayTitle == "(No title)")
        #expect(standup.displayTitle == "Standup")
        #expect(trimmedReminder.displayTitle == "Send notes")
    }

    @Test func tabOrder() {
        #expect(IslandTab.allCases == [.music, .camera, .calendar])
    }
}
