import Foundation
import Observation

@Observable @MainActor public final class AppState {
    public var mode: IslandMode = .collapsed {
        didSet {
            if mode == .collapsed && selectedTab != .music {
                // Reopening by hover must never implicitly reactivate the camera.
                // The selectedTab observer delivers the single collapsed context.
                selectedTab = .music
            } else {
                onCameraContextChange?(mode, selectedTab)
            }
        }
    }
    public var selectedTab: IslandTab = .music {
        didSet { onCameraContextChange?(mode, selectedTab) }
    }

    /// Deliver lifecycle changes synchronously; view updates may coalesce collapse/reopen.
    @ObservationIgnored public var onCameraContextChange: (@MainActor (IslandMode, IslandTab) -> Void)? {
        didSet { onCameraContextChange?(mode, selectedTab) }
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

    public var content: NowPlayingContent {
        NowPlayingContent(availability: spotifyAvailability, nowPlaying: nowPlaying)
    }

    public init() {}
}
