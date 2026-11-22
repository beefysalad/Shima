import Foundation

public enum SpotifyStatusKind: String, Equatable, Sendable {
    case running, notRunning, permissionDenied
}

public struct SpotifyStatusRow: Equatable, Sendable {
    public let kind: SpotifyStatusKind
    public let title: String
    public let detail: String
    public let buttonTitle: String
    public let buttonProminent: Bool
}

public enum SigningSummary: Equatable, Sendable {
    case adHoc
    case certificate(commonName: String, notAfter: Date?)
    case unreadable
}

public enum SettingsLinks {
    public static let automation = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
}

public enum SettingsText {
    public static let windowTitle = "shima Settings"
    public static let automationButton = "Open Automation Settings…"
    public static let quitButton = "Quit shima"
    public static let devicePopupsDetail = "A short banner under the notch when a Bluetooth device connects."
    public static let expiryWarningDays = 30

    /// `.running` only means no denial was seen since Spotify launched (M1 marks denial on error -1743).
    public static func spotifyRow(_ availability: SpotifyAvailability) -> SpotifyStatusRow {
        switch availability {
        case .running:
            SpotifyStatusRow(kind: .running, title: "Spotify is running",
                             detail: "Automation: allowed, or not asked yet.",
                             buttonTitle: automationButton, buttonProminent: false)
        case .notRunning:
            SpotifyStatusRow(kind: .notRunning, title: "Spotify is not running",
                             detail: "shima checks the Automation permission when Spotify runs.",
                             buttonTitle: automationButton, buttonProminent: false)
        case .permissionDenied:
            SpotifyStatusRow(kind: .permissionDenied, title: "shima can't control Spotify",
                             detail: "Allow it in System Settings › Privacy & Security › Automation › Shima.",
                             buttonTitle: automationButton, buttonProminent: true)
        }
    }

    public static func version(short: String?, build: String?) -> String {
        guard let short, !short.isEmpty else { return "Version unknown" }
        guard let build, !build.isEmpty else { return "Version \(short)" }
        return "Version \(short) (\(build))"
    }

    public static func signing(_ summary: SigningSummary, now: Date) -> String {
        switch summary {
        case .adHoc:
            return "Signed ad hoc (no certificate)"
        case .unreadable, .certificate(_, .none):
            return "Signing certificate: see docs"
        case let .certificate(name, notAfter?):
            let kind = name.split(separator: ":", maxSplits: 1).first.map(String.init) ?? name
            let day = utcDay(notAfter)
            if notAfter <= now { return "\(kind) certificate expired \(day); Automation must be granted again" }
            let days = Int((notAfter.timeIntervalSince(now) / 86_400).rounded(.down))
            if days < expiryWarningDays { return "\(kind) certificate expires \(day) (in \(days) days)" }
            return "\(kind) certificate expires \(day)"
        }
    }

    static func utcDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
