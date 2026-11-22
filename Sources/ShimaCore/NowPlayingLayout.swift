import CoreGraphics

/// Content geometry in the expanded island's local, top-left coordinates.
public enum NowPlayingLayout {
    public static let artwork = CGRect(x: 18, y: 50, width: 104, height: 104)
    public static let artworkRadius: CGFloat = 12
    public static let column = CGRect(x: 140, y: 48, width: 242, height: 140)
    public static let sourceTop: CGFloat = 48
    public static let titleTop: CGFloat = 72
    public static let artistTop: CGFloat = 94
    public static let progressTop: CGFloat = 123
    public static let timesTop: CGFloat = 132
    public static let titleSize: CGFloat = 16
    public static let artistSize: CGFloat = 12
    public static let timesSize: CGFloat = 10
    public static let progressHeight: CGFloat = 3

    public static let titleWidth: CGFloat = column.width
    public static var titleRect: CGRect { CGRect(x: column.minX, y: titleTop, width: titleWidth, height: 20) }

    /// Header tab icon: upper left of the open island, in the menu-bar-height strip left of the notch
    /// (the notch occupies x 110.5..289.5 of the 400 pt island). More tabs will follow it to the right.
    public static let tabIcon = CGRect(x: 14, y: 4, width: 28, height: 24)

    /// Settings gear: top right of the open island, below the notch strip and the 33 pt menu bar
    /// (status items there are other windows at the island's level).
    public static let settingsButton = CGRect(x: 358, y: 36, width: 24, height: 24)

    /// Centre in global top-left CG points; topY is the screen's top edge.
    public static func settingsButtonCenter(notchMidX: CGFloat, topY: CGFloat) -> CGPoint {
        CGPoint(x: notchMidX - IslandLayout.expanded.width / 2 + settingsButton.midX, y: topY + settingsButton.midY)
    }

    public static func controlRect(_ command: SpotifyCommand) -> CGRect {
        switch command {
        case .previous: CGRect(x: 140, y: 157, width: 28, height: 28)
        case .playPause: CGRect(x: 182, y: 155, width: 32, height: 32)
        case .next: CGRect(x: 228, y: 157, width: 28, height: 28)
        }
    }

    /// Centre in global top-left CG points; topY is the screen's top edge.
    public static func controlCenter(_ command: SpotifyCommand, notchMidX: CGFloat, topY: CGFloat) -> CGPoint {
        let rect = controlRect(command)
        return CGPoint(x: notchMidX - IslandLayout.expanded.width / 2 + rect.midX, y: topY + rect.midY)
    }

    public static let miniArtwork = CGSize(width: 20, height: 20)
    public static let miniArtworkRadius: CGFloat = 5
    public static let equalizer = CGSize(width: 16, height: 14)
    public static let barWidth: CGFloat = 2.5
    public static let barGap: CGFloat = 2
    public static let barCount = 4
}
