import CoreGraphics

/// Content geometry in the expanded island's local, top-left coordinates.
public enum NowPlayingLayout {
    public static let artwork = CGRect(x: 14, y: 44, width: 88, height: 88)
    public static let artworkRadius: CGFloat = 10
    public static let column = CGRect(x: 116, y: 44, width: 230, height: 100)
    public static let titleTop: CGFloat = 44
    public static let artistTop: CGFloat = 64
    public static let progressTop: CGFloat = 88
    public static let timesTop: CGFloat = 96
    public static let titleSize: CGFloat = 15
    public static let artistSize: CGFloat = 12.5
    public static let timesSize: CGFloat = 11
    public static let progressHeight: CGFloat = 4

    public static func controlRect(_ command: SpotifyCommand) -> CGRect {
        switch command {
        case .previous: CGRect(x: 173, y: 114, width: 28, height: 28)
        case .playPause: CGRect(x: 215, y: 112, width: 32, height: 32)
        case .next: CGRect(x: 261, y: 114, width: 28, height: 28)
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
