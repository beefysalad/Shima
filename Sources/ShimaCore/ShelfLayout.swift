import CoreGraphics

/// Home tab and drag veil geometry in the expanded island's local, top-left coordinates (400 x 200 pt),
/// copied exactly from the `SH` table in mockup/index.html. Everything sits below the 32 pt header strip.
public enum ShelfLayout {
    /// Drag veil: covers the content area below the header strip, on any tab.
    public static let veil = CGRect(x: 0, y: 32, width: 400, height: 168)
    public static let veilTileRow = CGRect(x: 0, y: 52, width: 400, height: 96)
    public static let veilTile = CGRect(x: 120, y: 52, width: 160, height: 96)
    public static let veilTileRadius: CGFloat = 14
    public static let veilIcon = CGRect(x: 186, y: 70, width: 28, height: 28)
    public static let veilCaption = CGRect(x: 120, y: 110, width: 160, height: 16)
    public static let veilCount = CGRect(x: 12, y: 156, width: 376, height: 16)

    /// Home tab.
    public static let chipRow = CGRect(x: 14, y: 44, width: 372, height: 64)
    public static let chipSize = CGSize(width: 116, height: 64)
    public static let chipRadius: CGFloat = 10
    public static let chipGap: CGFloat = 8
    public static let emptyState = CGRect(x: 14, y: 44, width: 372, height: 88)
    public static let statusLine = CGRect(x: 14, y: 116, width: 372, height: 16)
    public static let countLabel = CGRect(x: 14, y: 166, width: 200, height: 20)
    public static let clearButton = CGRect(x: 326, y: 166, width: 60, height: 22)

    /// The chip's remove (x) button, offset from the chip's top-left corner.
    public static func chipRemove(chipX: CGFloat, chipY: CGFloat) -> CGRect {
        CGRect(x: chipX + 96, y: chipY + 4, width: 16, height: 16)
    }

    /// The Home icon's "shelf has items" dot: 6 pt, 3 pt in from the icon's top-right corner.
    public static var homeDot: CGRect {
        let home = NowPlayingLayout.tabRect(.home)
        return CGRect(x: home.maxX - 3 - 6, y: home.minY + 3, width: 6, height: 6)
    }
}
