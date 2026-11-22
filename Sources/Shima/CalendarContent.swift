import SwiftUI
import ShimaCore

/// The Calendar tab as drawn in mockup/index.html: the selected day and its events and due reminders on the left,
/// the month grid on the right. Geometry is `CalendarLayout` (spec "Layout table"); the view is only mounted while
/// the tab is open, so nothing here runs while the island is closed.
struct CalendarContent: View {
    let coordinator: CalendarCoordinator
    /// Injectable so offscreen renders are deterministic.
    var now: () -> Date = { Date() }

    private let accent = Color(red: 224 / 255, green: 122 / 255, blue: 79 / 255)
    private let doneBlue = Color(red: 134 / 255, green: 174 / 255, blue: 247 / 255)
    private let ink2 = Color.white.opacity(0.62)
    private let ink3 = Color.white.opacity(0.52)
    private var calendar: Calendar { .autoupdatingCurrent }

    var body: some View {
        let model = coordinator.model
        let now = now()
        ZStack(alignment: .topLeading) {
            left(model, now: now)
            right(model, now: now)
        }
        .foregroundStyle(.white)
        .frame(width: IslandLayout.expanded.width, height: IslandLayout.expanded.height, alignment: .topLeading)
    }

    // MARK: Left column

    private func left(_ model: CalendarModel, now: Date) -> some View {
        ZStack(alignment: .topLeading) {
            dateHeader(model.selectedDay)
            Text("\(calendar.component(.day, from: model.selectedDay))")
                .font(.system(size: 30, weight: .bold)).monospacedDigit()
                .frame(width: CalendarLayout.dayNumber.width, height: CalendarLayout.dayNumber.height, alignment: .leading)
                .position(x: CalendarLayout.dayNumber.midX, y: CalendarLayout.dayNumber.midY)
            content(model, now: now)
        }
    }

    private func dateHeader(_ day: Date) -> some View {
        HStack(spacing: 6) {
            Text(formatted(day, "EEE").uppercased()).foregroundStyle(accent).fontWeight(.bold)
            Rectangle().fill(Color.white.opacity(0.13)).frame(width: 1, height: 9)
            Text(formatted(day, "MMM").uppercased()).foregroundStyle(ink2)
        }
        .font(.system(size: 11, weight: .semibold)).tracking(0.3)
        .frame(width: CalendarLayout.dateLine.width, height: CalendarLayout.dateLine.height, alignment: .leading)
        .position(x: CalendarLayout.dateLine.midX, y: CalendarLayout.dateLine.midY)
    }

    @ViewBuilder private func content(_ model: CalendarModel, now: Date) -> some View {
        let eventsDenied = model.eventsAccess == .denied
        let remindersDenied = model.remindersAccess == .denied
        if model.eventsAccess == .notDetermined && model.remindersAccess == .notDetermined {
            note("Allow Calendar and Reminders access in the system prompt.")
        } else if eventsDenied || remindersDenied {
            let denied: [(String, String)] = [(eventsDenied ? "Calendar" : "", "Privacy_Calendars"),
                                              (remindersDenied ? "Reminders" : "", "Privacy_Reminders")].filter { !$0.0.isEmpty }
            // With one store still readable, its rows keep the top two slots and the notice takes the lower box.
            let cap = denied.count == 2 ? 0 : 2
            if cap > 0 { rows(model, now: now, cap: cap) }
            ForEach(Array(denied.enumerated()), id: \.offset) { i, item in
                deniedBox(item.0, pane: item.1, rect: CalendarLayout.deniedBoxes[denied.count == 2 ? i : 1])
            }
        } else {
            rows(model, now: now, cap: CalendarLayout.maxRows)
        }
    }

    @ViewBuilder private func rows(_ model: CalendarModel, now: Date, cap: Int) -> some View {
        let column = CalendarContentRules.leftColumn(
            events: model.events, reminders: model.reminders, selectedDay: model.selectedDay,
            now: now, calendar: calendar, cap: cap)
        if column.rows.isEmpty {
            note("Nothing scheduled")
        } else {
            ForEach(Array(column.rows.enumerated()), id: \.element.rowID) { index, row in
                rowView(row, now: now)
                    .frame(width: CalendarLayout.rowsWidth, height: CalendarLayout.rowHeight, alignment: .leading)
                    .position(x: CalendarLayout.row(index).midX, y: CalendarLayout.row(index).midY)
                    .transition(.opacity)
            }
            if column.overflow > 0 {
                Text("+\(column.overflow) more")
                    .font(.system(size: 10)).foregroundStyle(ink3)
                    .frame(width: CalendarLayout.moreLine.width, height: CalendarLayout.moreLine.height, alignment: .leading)
                    .position(x: CalendarLayout.moreLine.midX, y: CalendarLayout.row(column.rows.count - 1).maxY + 4 + CalendarLayout.moreLine.height / 2)
            }
        }
    }

    @ViewBuilder private func rowView(_ row: LeftRow, now: Date) -> some View {
        switch row {
        case .event(let event, let phase):
            let color = eventColor(event)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1).fill(color).frame(width: CalendarLayout.eventBarWidth)
                Text(event.displayTitle).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(timeText(event, phase: phase)).font(.system(size: 9.5)).monospacedDigit().lineLimit(1)
                    .fontWeight(phase == .running ? .semibold : .regular)
                    .foregroundStyle(phase == .running ? color : ink2).fixedSize()
            }
        case .reminder(let item, let overdue):
            HStack(spacing: 7) {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { coordinator.complete(item) }
                } label: {
                    Circle().strokeBorder(ink3, lineWidth: 1.2)
                        .frame(width: CalendarLayout.reminderCircle, height: CalendarLayout.reminderCircle)
                        .frame(width: CalendarLayout.reminderHit.width, height: CalendarLayout.reminderHit.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete \(item.displayTitle)")
                Text(item.displayTitle).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(overdue ? "Overdue" : "Today").font(.system(size: 10)).lineLimit(1)
                    .foregroundStyle(overdue ? accent : ink2).fixedSize()
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(ink3).fixedSize(horizontal: false, vertical: true)
            .frame(width: CalendarLayout.emptyLine.width, height: CalendarLayout.emptyLine.height, alignment: .topLeading)
            .position(x: CalendarLayout.emptyLine.midX, y: CalendarLayout.emptyLine.midY)
    }

    private func deniedBox(_ store: String, pane: String, rect: CGRect) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(store) access is off").font(.system(size: 11, weight: .semibold))
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("Open Settings").font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 8).frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.13)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(width: rect.width, height: rect.height, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.075)))
        .position(x: rect.midX, y: rect.midY)
    }

    // MARK: Right column

    private func right(_ model: CalendarModel, now: Date) -> some View {
        let grid = MonthGrid.make(month: model.displayedMonth, today: now, calendar: calendar)
        let dots = CalendarContentRules.dotDays(events: model.events, in: grid, calendar: calendar)
        return ZStack(alignment: .topLeading) {
            Button { coordinator.goToToday() } label: {
                monthTitle(grid.title)
                    .frame(width: CalendarLayout.monthTitle.width, height: CalendarLayout.monthTitle.height, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go to today")
            .position(x: CalendarLayout.monthTitle.midX, y: CalendarLayout.monthTitle.midY)
            navButton("chevron.left", "Previous month", CalendarLayout.previousMonth) { coordinator.showMonth(offset: -1) }
            navButton("chevron.right", "Next month", CalendarLayout.nextMonth) { coordinator.showMonth(offset: 1) }
            HStack(spacing: 0) {
                ForEach(Array(grid.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(ink3).frame(maxWidth: .infinity)
                }
            }
            .frame(width: CalendarLayout.weekdayRow.width, height: CalendarLayout.weekdayRow.height)
            .position(x: CalendarLayout.weekdayRow.midX, y: CalendarLayout.weekdayRow.midY)
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { w, week in
                ForEach(Array(week.enumerated()), id: \.offset) { d, day in
                    dayCell(day, rect: CalendarLayout.cell(week: w, day: d), selected: calendar.isDate(day.date, inSameDayAs: model.selectedDay),
                            hasEvent: dots.contains(calendar.startOfDay(for: day.date)))
                }
            }
        }
    }

    /// The month name is the accent colour and the year white, as in the mockup. Text concatenation keeps one baseline.
    private func monthTitle(_ title: String) -> some View {
        let parts = title.split(separator: " ")
        let year = parts.last.map(String.init) ?? ""
        let month = parts.dropLast().joined(separator: " ")
        return HStack(spacing: 4) {
            Text(month).foregroundStyle(accent)
            Text(year).foregroundStyle(Color.white)
        }
        .font(.system(size: 12, weight: .bold)).tracking(0.2).lineLimit(1)
    }

    private func navButton(_ symbol: String, _ label: String, _ rect: CGRect, action: @escaping @MainActor () -> Void) -> some View {
        Button { action() } label: {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(ink2)
                .frame(width: rect.width, height: rect.height).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .position(x: rect.midX, y: rect.midY)
    }

    private func dayCell(_ day: GridDay, rect: CGRect, selected: Bool, hasEvent: Bool) -> some View {
        Button { coordinator.selectDay(day.date) } label: {
            ZStack {
                if selected && !day.isToday {
                    Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5)
                        .frame(width: CalendarLayout.dayCircle, height: CalendarLayout.dayCircle)
                }
                Text("\(day.dayNumber)")
                    .font(.system(size: 11, weight: day.isToday ? .heavy : (day.inMonth ? .semibold : .regular))).monospacedDigit()
                    .foregroundStyle(day.isToday ? accent : (day.inMonth ? Color.white : ink3))
                if hasEvent {
                    Circle().fill(doneBlue).frame(width: CalendarLayout.dotSize, height: CalendarLayout.dotSize)
                        .offset(y: rect.height / 2 - CalendarLayout.dotSize / 2 - 0.5)
                }
            }
            .frame(width: rect.width, height: rect.height).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(formatted(day.date, "EEEE d MMMM"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .position(x: rect.midX, y: rect.midY)
    }

    // MARK: Formatting

    private func formatted(_ date: Date, _ template: String) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = calendar.locale ?? .current
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }

    /// "9:30" or "21:30": no leading zero and no AM/PM, so a time range stays short in the 158 pt column.
    private func clock(_ date: Date) -> String {
        let locale = calendar.locale ?? .current
        let twelveHour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)?.contains("a") ?? false
        var hour = calendar.component(.hour, from: date)
        if twelveHour { hour = hour % 12 == 0 ? 12 : hour % 12 }
        return String(format: "%d:%02d", hour, calendar.component(.minute, from: date))
    }

    private func timeText(_ event: CalendarEvent, phase: EventPhase) -> String {
        if event.isAllDay { return "All day" }
        let range = "\(clock(event.start))–\(clock(event.end))"
        return phase == .running ? "Now · " + range : range
    }

    private func eventColor(_ event: CalendarEvent) -> Color {
        guard event.colorRGB.count >= 3 else { return Color(red: 200 / 255, green: 107 / 255, blue: 224 / 255) }
        return Color(red: event.colorRGB[0], green: event.colorRGB[1], blue: event.colorRGB[2])
    }
}

private extension LeftRow {
    var rowID: String {
        switch self {
        case .event(let event, _): "e-" + event.id
        case .reminder(let item, _): "r-" + item.id
        }
    }
}
