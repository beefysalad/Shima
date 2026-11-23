import Foundation

/// True while a drag that this app started (a shelf chip) is in flight. The drop destination ignores such
/// drags (spike 3: the island otherwise receives its own chip drags). The chip drag source sets it.
/// The flag expires after `maxAge`, so a missed `draggingSession(_:endedAt:)` (for example when SwiftUI removes
/// the chip's view mid-session) can never make the island refuse external drops until relaunch.
@MainActor enum OwnDrag {
    static let maxAge: TimeInterval = 120
    static var now: () -> Date = Date.init
    private static var startedAt: Date?

    static var active: Bool {
        get {
            guard let startedAt else { return false }
            if now().timeIntervalSince(startedAt) > maxAge {
                self.startedAt = nil
                return false
            }
            return true
        }
        set { startedAt = newValue ? now() : nil }
    }
}
