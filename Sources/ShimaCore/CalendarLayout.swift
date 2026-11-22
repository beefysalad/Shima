import CoreGraphics

/// Calendar tab geometry in the open island's local, top-left coordinates (points).
/// Every value comes from the "Layout table" in docs/superpowers/specs/2026-11-23-calendar-reminders-design.md
/// (approved mockup/index.html, Calendar tab). Nothing but the header icons sits above y 34, so the notch zone stays clear.
public enum CalendarLayout {
    // Left column (x 18..176)
    public static let dateLine = CGRect(x: 18, y: 38, width: 158, height: 14)
    public static let dayNumber = CGRect(x: 18, y: 50, width: 158, height: 36)
    public static let maxRows = 4
    public static let rowHeight: CGFloat = 17
    public static let rowPitch: CGFloat = 19
    public static let rowsTop: CGFloat = 92
    public static let rowsWidth: CGFloat = 158
    public static let moreLine = CGRect(x: 18, y: 170, width: 158, height: 12)
    public static let emptyLine = CGRect(x: 18, y: 92, width: 158, height: 30)
    public static let deniedBoxes = [CGRect(x: 18, y: 92, width: 158, height: 40), CGRect(x: 18, y: 138, width: 158, height: 40)]
    /// Event colour bar, reminder circle, and the text gap.
    public static let eventBarWidth: CGFloat = 2
    public static let reminderCircle: CGFloat = 11
    public static let reminderHit = CGSize(width: 18, height: 17)
    public static let rowGap: CGFloat = 8

    public static func row(_ index: Int) -> CGRect {
        CGRect(x: 18, y: rowsTop + CGFloat(index) * rowPitch, width: rowsWidth, height: rowHeight)
    }

    // Right column (x 196..386)
    public static let monthTitle = CGRect(x: 196, y: 38, width: 150, height: 18)
    public static let previousMonth = CGRect(x: 350, y: 38, width: 18, height: 18)
    public static let nextMonth = CGRect(x: 368, y: 38, width: 18, height: 18)
    public static let weekdayRow = CGRect(x: 196, y: 58, width: 190, height: 12)
    public static let gridOrigin = CGPoint(x: 196, y: 72)
    public static let cellSize = CGSize(width: 190.0 / 7.0, height: 19)
    public static let maxWeeks = 6
    public static let dayCircle: CGFloat = 17
    public static let dotSize: CGFloat = 3

    public static func cell(week: Int, day: Int) -> CGRect {
        CGRect(x: gridOrigin.x + CGFloat(day) * cellSize.width, y: gridOrigin.y + CGFloat(week) * cellSize.height,
               width: cellSize.width, height: cellSize.height)
    }

    /// Centre in global top-left CG points; topY is the screen's top edge.
    public static func center(of rect: CGRect, notchMidX: CGFloat, topY: CGFloat) -> CGPoint {
        CGPoint(x: notchMidX - IslandLayout.expanded.width / 2 + rect.midX, y: topY + rect.midY)
    }
}
