import AppKit
import SwiftUI
import ShimaCore

/// Renders the Calendar tab offscreen (no window, no Screen Recording) to PNG for comparison with mockup/index.html.
/// Usage: render-calendar <output-dir>. Fixed clock: Fri 20 Nov 2026 9:41, the mockup's.
@main struct RenderCalendar {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let out = CommandLine.arguments.dropFirst().first ?? "."
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        var cal = Calendar.autoupdatingCurrent
        cal.timeZone = .current
        func at(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 11) -> Date {
            cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
        }
        let now = at(20, 9, 41)
        let purple = [200.0 / 255, 107.0 / 255, 224.0 / 255], blue = [77.0 / 255, 163.0 / 255, 1.0], green = [52.0 / 255, 199.0 / 255, 89.0 / 255], orange = [1.0, 159.0 / 255, 10.0 / 255]
        func event(_ id: String, _ title: String, _ start: Date, _ end: Date, _ color: [Double], allDay: Bool = false) -> CalendarEvent {
            CalendarEvent(id: id, title: title, start: start, end: end, isAllDay: allDay, colorRGB: color)
        }
        var base = [event("e1", "Standup", at(20, 9, 30), at(20, 10, 0), purple), event("e2", "Design review", at(20, 11, 0), at(20, 12, 0), blue)]
        for d in [3, 9, 13, 27] { base.append(event("d\(d)", "Dentist", at(d, 15, 0), at(d, 15, 45), blue)) }
        let busy = base + [event("e3", "Lunch with Mika", at(20, 12, 30), at(20, 13, 30), green),
                           event("e4", "Mika’s birthday", at(20, 0, 0), at(21, 0, 0), orange, allDay: true),
                           event("e5", "Gym", at(20, 18, 0), at(20, 19, 0), green)]
        let reminders = [ReminderItem(id: "r1", title: "Reply to landlord", due: at(19, 17, 0), isCompleted: false),
                         ReminderItem(id: "r2", title: "Renew passport", due: at(20, 17, 0), isCompleted: false)]

        func render(_ name: String, access: CalendarAccess = .authorized, events: [CalendarEvent], reminders: [ReminderItem], monthOffset: Int = 0) {
            let client = FakeCalendarClient(eventsAccess: access, remindersAccess: access)
            client.events = events
            client.reminders = reminders
            let coordinator = CalendarCoordinator(client: client, calendar: cal, now: { now })
            coordinator.setContext(mode: .expanded, tab: .calendar, screenAvailable: true)
            if monthOffset != 0 { coordinator.showMonth(offset: monthOffset) }
            let scale: CGFloat = 3
            let view = ZStack(alignment: .topLeading) {
                Color.black
                CalendarContent(coordinator: coordinator, now: { now })
            }
            .frame(width: IslandLayout.expanded.width, height: IslandLayout.expanded.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: IslandLayout.expanded.width * scale, height: IslandLayout.expanded.height * scale, alignment: .topLeading)
            let host = NSHostingView(rootView: view)
            host.frame = CGRect(x: 0, y: 0, width: IslandLayout.expanded.width * scale, height: IslandLayout.expanded.height * scale)
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("no bitmap") }
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = rep.representation(using: .png, properties: [:])!
            try! png.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
            print("rendered \(name)")
        }
        render("allowed", events: base, reminders: reminders)
        render("busy", events: busy, reminders: reminders)
        render("sixweek", events: base, reminders: reminders, monthOffset: -6)
        render("denied", access: .denied, events: [], reminders: [])
        render("empty", events: [], reminders: [])
    }
}
