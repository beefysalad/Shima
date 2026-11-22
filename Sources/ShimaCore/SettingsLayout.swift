import CoreGraphics

/// Settings window content geometry, top-left points. Fixed (the window is not resizable) so scripts can
/// click by coordinates; `SettingsLayoutTests` pins the click points that scripts/verify-settings.sh copies.
public enum SettingsLayout {
    public static let size = CGSize(width: 440, height: 510)

    public static let generalHeader = CGRect(x: 20, y: 12, width: 400, height: 18)
    public static let launchAtLogin = CGRect(x: 20, y: 38, width: 300, height: 24)
    public static let equalizerLabel = CGRect(x: 20, y: 94, width: 110, height: 28)

    public static func equalizerSegment(_ mode: EqualizerMode) -> CGRect {
        let index = CGFloat(EqualizerMode.allCases.firstIndex(of: mode) ?? 0)
        return CGRect(x: 140 + 90 * index, y: 94, width: 90, height: 28)
    }

    public static let spotifyHeader = CGRect(x: 20, y: 144, width: 400, height: 18)
    public static let spotifyTitle = CGRect(x: 20, y: 170, width: 400, height: 18)
    public static let spotifyDetail = CGRect(x: 20, y: 190, width: 400, height: 30)
    public static let automationButton = CGRect(x: 20, y: 226, width: 230, height: 28)

    public static let aboutHeader = CGRect(x: 20, y: 270, width: 400, height: 18)
    public static let version = CGRect(x: 20, y: 296, width: 400, height: 16)
    public static let signing = CGRect(x: 20, y: 314, width: 400, height: 16)
    public static let quitButton = CGRect(x: 320, y: 470, width: 100, height: 28)

    public static let updatesHeader = CGRect(x: 20, y: 350, width: 400, height: 18)
    public static let updateStatus = CGRect(x: 20, y: 376, width: 400, height: 48)
    public static let updateActions = CGRect(x: 20, y: 430, width: 400, height: 28)

    /// The checkbox sits at the toggle's leading edge.
    public static var launchAtLoginClick: CGPoint { CGPoint(x: launchAtLogin.minX + 8, y: launchAtLogin.midY) }

    public static func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    public static var allRects: [CGRect] {
        [generalHeader, launchAtLogin, equalizerLabel] + EqualizerMode.allCases.map(equalizerSegment)
            + [spotifyHeader, spotifyTitle, spotifyDetail, automationButton, aboutHeader, version, signing, updatesHeader, updateStatus, updateActions, quitButton]
    }
}
