import CoreGraphics

/// Window and diagnostic click regions for the native Settings shell.
/// Content uses SwiftUI layout; scripts/verify-settings.sh copies the click points.
public enum SettingsLayout {
    public static let size = CGSize(width: 880, height: 620)
    public static let sidebarWidth: CGFloat = 200

    public static func navigation(_ page: SettingsPage) -> CGRect {
        let index = SettingsPage.allCases.firstIndex(of: page) ?? 0
        return CGRect(x: 12, y: 124 + 38 * index, width: 176, height: 34)
    }
    public static let quitButton = CGRect(x: 12, y: 570, width: 176, height: 38)
    public static let launchAtLoginClick = CGPoint(x: 815, y: 68)
    public static func equalizerClick(_ mode: EqualizerMode) -> CGPoint {
        let index = EqualizerMode.allCases.firstIndex(of: mode) ?? 0
        return CGPoint(x: 296 + 119 * index, y: 270)
    }
    public static let automationClick = CGPoint(x: 350, y: 130)
    public static func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
}

public enum SettingsPage: String, CaseIterable, Sendable {
    case general = "General", music = "Music", updates = "Updates", about = "About"
    public var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .music: "music.note"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }
    public var subtitle: String {
        switch self {
        case .general: "Make shima feel at home on your Mac."
        case .music: "Your music, connected to the notch."
        case .updates: "The latest improvements, in one place."
        case .about: "A small, local companion for your Mac."
        }
    }
}
