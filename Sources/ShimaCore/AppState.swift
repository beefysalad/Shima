import Foundation
import Observation

@Observable @MainActor public final class AppState {
    public var mode: IslandMode = .collapsed

    public var live: Bool = false
    public var nowPlaying: NowPlaying? = nil
    public var spotifyAvailability: SpotifyAvailability = .notRunning

    public var content: NowPlayingContent {
        NowPlayingContent(availability: spotifyAvailability, nowPlaying: nowPlaying)
    }

    public init() {}
}
