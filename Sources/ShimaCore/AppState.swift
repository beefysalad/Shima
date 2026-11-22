import Foundation
import Observation

@Observable @MainActor public final class AppState {
    public var mode: IslandMode = .collapsed

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

    public var content: NowPlayingContent {
        NowPlayingContent(availability: spotifyAvailability, nowPlaying: nowPlaying)
    }

    public init() {}
}
