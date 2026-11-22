import AppKit
import ShimaCore

/// Broadcast and workspace observers for Spotify. They only report events: no Apple Event is sent from here.
@MainActor
final class SpotifyObservers: NSObject {
    private static let bundleID = "com.spotify.client"
    private let onEvent: @MainActor (SpotifyEvent) -> Void
    private var workspaceTokens: [NSObjectProtocol] = []
    private var started = false

    init(onEvent: @escaping @MainActor (SpotifyEvent) -> Void) {
        self.onEvent = onEvent
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(playbackChanged(_:)),
            name: .init("com.spotify.client.PlaybackStateChanged"),
            object: nil, suspensionBehavior: .deliverImmediately)
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let id = Self.bundleID(of: note)
            MainActor.assumeIsolated { if id == Self.bundleID { self?.onEvent(.launched) } }
        })
        workspaceTokens.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let id = Self.bundleID(of: note)
            MainActor.assumeIsolated { if id == Self.bundleID { self?.onEvent(.terminated) } }
        })
    }

    /// Parse in the callback: only Sendable values cross into the main-actor closure.
    @objc nonisolated private func playbackChanged(_ note: Notification) {
        let reading = SpotifyReading(notification: note.userInfo ?? [:])
        let at = Date()
        MainActor.assumeIsolated {
            if let reading {
                onEvent(.reading(reading, source: .notification, at: at))
            } else {
                Log.spotify.info("spotify broadcast unparsed")
            }
        }
    }

    nonisolated private static func bundleID(of note: Notification) -> String? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }
}
