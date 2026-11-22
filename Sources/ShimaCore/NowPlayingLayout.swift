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

    /// Header icons, upper left of the open island in the menu-bar-height strip left of the notch
    /// (the notch occupies x 110.5..289.5 of the 400 pt island): Home (opens Settings), then one icon per tab
    /// in `IslandTab.allCases` order (Music, Camera, Calendar). 22 x 22 pt hit areas on a 24 pt pitch with a 14 pt
    /// outlined glyph, matching mockup/index.html. The last icon ends at x 106, clear of the notch.
    public static let headerPitch: CGFloat = 24
    public static let tabIcon = CGRect(x: 36, y: 5, width: 22, height: 22)

    public static func tabRect(_ tab: IslandTab) -> CGRect {
        let index = IslandTab.allCases.firstIndex(of: tab) ?? 0
        return tabIcon.offsetBy(dx: CGFloat(index) * headerPitch, dy: 0)
    }

    /// Home button: first icon of the header. It opens the Settings window (it replaces the old gear).
    public static let settingsButton = CGRect(x: 12, y: 5, width: 22, height: 22)

    /// Camera tab, as in the mockup: the preview on the left, a column of Live / Mirror / Switch camera / Close / note on the right.
    public static let cameraPreview = CGRect(x: 14, y: 40, width: 258, height: 146)
    public static let cameraLive = CGRect(x: 282, y: 40, width: 104, height: 16)
    public static let cameraMirror = CGRect(x: 282, y: 61, width: 104, height: 30)
    public static let cameraSwitch = CGRect(x: 282, y: 96, width: 104, height: 30)
    public static let cameraClose = CGRect(x: 282, y: 131, width: 104, height: 30)
    public static let cameraNote = CGRect(x: 282, y: 165, width: 104, height: 21)

    /// Centre in global top-left CG points; topY is the screen's top edge.
    public static func settingsButtonCenter(notchMidX: CGFloat, topY: CGFloat) -> CGPoint {
        CGPoint(x: notchMidX - IslandLayout.expanded.width / 2 + settingsButton.midX, y: topY + settingsButton.midY)
    }

    /// The three controls span 116 pt and are centred in the text column (x 203..319 of the 400 pt island).
    public static let controlsMinX: CGFloat = column.midX - 58

    public static func controlRect(_ command: SpotifyCommand) -> CGRect {
        switch command {
        case .previous: CGRect(x: controlsMinX, y: 157, width: 28, height: 28)
        case .playPause: CGRect(x: controlsMinX + 42, y: 155, width: 32, height: 32)
        case .next: CGRect(x: controlsMinX + 88, y: 157, width: 28, height: 28)
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
