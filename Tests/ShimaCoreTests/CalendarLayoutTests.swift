import CoreGraphics
import Testing
@testable import ShimaCore

@Suite struct CalendarLayoutTests {
    let island = CGRect(x: 0, y: 0, width: 400, height: 200)
    let notchZone = CGRect(x: 110.5, y: 0, width: 179, height: 32)

    var singles: [CGRect] {
        [CalendarLayout.dateLine, CalendarLayout.dayNumber, CalendarLayout.moreLine, CalendarLayout.emptyLine,
         CalendarLayout.monthTitle, CalendarLayout.previousMonth, CalendarLayout.nextMonth, CalendarLayout.weekdayRow]
        + CalendarLayout.deniedBoxes
    }

    @Test func everythingIsInsideTheIslandBelowTheNotchStrip() {
        for r in singles { #expect(island.contains(r) && r.minY >= 34) }
        for i in 0..<CalendarLayout.maxRows { let r = CalendarLayout.row(i); #expect(island.contains(r) && r.minY >= 34) }
        for w in 0..<CalendarLayout.maxWeeks { for d in 0..<7 { #expect(island.contains(CalendarLayout.cell(week: w, day: d))) } }
    }

    @Test func nothingTouchesTheNotchZone() {
        for r in singles { #expect(!r.intersects(notchZone)) }
    }

    @Test func leftAndRightColumnsDoNotOverlap() {
        let left = singles.filter { $0.maxX <= 176 }
        let right = singles.filter { $0.minX >= 196 }
        #expect(left.count + right.count == singles.count)
        for l in left { for r in right { #expect(!l.intersects(r)) } }
    }

    @Test func fourRowsAndTheMoreLineFitInOrder() {
        let last = CalendarLayout.row(CalendarLayout.maxRows - 1)
        #expect(last == CGRect(x: 18, y: 149, width: 158, height: 17))
        #expect(last.maxY < CalendarLayout.moreLine.minY && CalendarLayout.moreLine.maxY <= 186)
        #expect(CalendarLayout.dayNumber.maxY <= CalendarLayout.row(0).minY)
        #expect(CalendarLayout.deniedBoxes[0].maxY < CalendarLayout.deniedBoxes[1].minY)
    }

    @Test func sixWeekGridEndsAboveTheRoundedBottom() {
        #expect(CalendarLayout.cell(week: 5, day: 6).maxY == 186)
        #expect(CalendarLayout.cell(week: 0, day: 0).minX == 196)
        #expect(abs(CalendarLayout.cell(week: 0, day: 6).maxX - 386) < 0.001)
        #expect(CalendarLayout.cell(week: 0, day: 0).minY >= CalendarLayout.weekdayRow.maxY)
    }

    @Test func monthNavigationSitsRightOfTheTitle() {
        #expect(CalendarLayout.monthTitle.maxX <= CalendarLayout.previousMonth.minX)
        #expect(CalendarLayout.previousMonth.maxX <= CalendarLayout.nextMonth.minX)
        #expect(CalendarLayout.nextMonth.maxX == 386)
    }
}
