import Foundation

@MainActor public final class SpotifyCoordinator {
    public private(set) var model = SpotifyModel()
    public var onLiveChange: (@MainActor (Bool) -> Void)?
    public var onChanges: (@MainActor ([SpotifyChange]) -> Void)?
    public var onArtwork: (@MainActor (_ trackID: String?, _ url: URL?) -> Void)?
    private let client: any SpotifyClient
    private let state: AppState
    private var artworkAskedFor: String?

    public init(client: any SpotifyClient, state: AppState) {
        self.client = client
        self.state = state
    }

    public func handle(_ event: SpotifyEvent) {
        let wasLive = model.isLive
        let oldArt = (model.nowPlaying?.trackID, model.nowPlaying?.artworkURL)
        let (np, changes) = model.apply(event)
        state.nowPlaying = np
        state.spotifyAvailability = model.availability

        if !changes.isEmpty { onChanges?(changes) }
        if model.isLive != wasLive { onLiveChange?(model.isLive) }
        if (np?.trackID, np?.artworkURL) != oldArt { onArtwork?(np?.trackID, np?.artworkURL) }

        if case .terminated = event {
            client.invalidate()
            artworkAskedFor = nil
        }

        // Keep refresh last: the fake can synchronously deliver a newer reading.
        guard case let .reading(reading, source: .notification, _) = event,
              model.availability != .notRunning else { return }
        let needsArtwork = np.map { $0.artworkURL == nil && artworkAskedFor != $0.trackID } ?? false
        guard model.availability == .permissionDenied || !reading.hasDisplayFields || needsArtwork else { return }
        if needsArtwork { artworkAskedFor = np?.trackID }
        client.refresh()
    }

    public func islandOpened() {
        guard model.availability != .notRunning else { return }
        client.refresh()
    }

    public func perform(_ command: SpotifyCommand) {
        guard model.availability == .running else { return }
        client.send(command)
    }
}
