import Foundation
import Observation

@Observable @MainActor public final class AppState {
    public var mode: IslandMode = .collapsed {
        didSet {
            if mode == .collapsed && selectedTab != .music {
                // Reopening by hover must return to Music.
                // The selectedTab observer delivers the single collapsed context.
                selectedTab = .music
            } else {
                notifyTabContextObservers()
            }
        }
    }
    public var selectedTab: IslandTab = .music {
        didSet { notifyTabContextObservers() }
    }

    @ObservationIgnored private var tabContextObservers: [(id: UUID, handler: @MainActor (IslandMode, IslandTab) -> Void)] = []

    /// Deliver lifecycle changes synchronously; view updates may coalesce collapse/reopen.
    @discardableResult
    public func addTabContextObserver(_ handler: @escaping @MainActor (IslandMode, IslandTab) -> Void) -> UUID {
        let id = UUID()
        tabContextObservers.append((id, handler))
        handler(mode, selectedTab)
        return id
    }

    public func removeTabContextObserver(_ id: UUID) {
        tabContextObservers.removeAll { $0.id == id }
    }

    private func notifyTabContextObservers() {
        let context = (mode, selectedTab)
        for observer in tabContextObservers {
            observer.handler(context.0, context.1)
        }
    }

    public var live: Bool = false
    public var nowPlaying: NowPlaying? = nil {
        didSet {
            guard oldValue?.trackID != nowPlaying?.trackID || oldValue?.artworkURL != nowPlaying?.artworkURL else { return }
            onArtworkChange?(nowPlaying?.trackID, nowPlaying?.artworkURL)
        }
    }

    /// Synchronous identity delivery prevents render coalescing from hiding a track
    /// change or termination from the artwork loader. Binding also supplies initial state.
    @ObservationIgnored public var onArtworkChange: (@MainActor (String?, URL?) -> Void)? {
        didSet { onArtworkChange?(nowPlaying?.trackID, nowPlaying?.artworkURL) }
    }
    public var spotifyAvailability: SpotifyAvailability = .notRunning

    /// Applied by `SettingsModel` at launch and when changed in the Settings window.
    public var equalizerMode: EqualizerMode = .animated
    public var devicePopupsEnabled = true
    public var peek: PeekItem?

    public var content: NowPlayingContent {
        NowPlayingContent(availability: spotifyAvailability, nowPlaying: nowPlaying)
    }

    public init() {}
}
