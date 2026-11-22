import Foundation

@MainActor public final class SpotifyCoordinator {
    public private(set) var model = SpotifyModel()
    public var onLiveChange: (@MainActor (Bool) -> Void)?
    public var onChanges: (@MainActor ([SpotifyChange]) -> Void)?
    public var onArtwork: (@MainActor (_ trackID: String?, _ url: URL?) -> Void)?
    public static let commandFollowUpDelay: Duration = .milliseconds(250)
    private let client: any SpotifyClient
    private let state: AppState
    private let scheduler: any Scheduler
    private var artworkAskedFor: String?
    private var followUp: (any ScheduledTask)?

    public init(client: any SpotifyClient, state: AppState, scheduler: any Scheduler) {
        self.client = client
        self.state = state
        self.scheduler = scheduler
    }

    public func handle(_ event: SpotifyEvent) {
        if case .commandSucceeded = event {
            scheduleFollowUp()
            return
        }
        let wasLive = model.isLive
        let oldArt = (model.nowPlaying?.trackID, model.nowPlaying?.artworkURL)
        let (np, changes) = model.apply(event)
        state.nowPlaying = np
        state.spotifyAvailability = model.availability

        if !changes.isEmpty { onChanges?(changes) }
        if model.isLive != wasLive { onLiveChange?(model.isLive) }
        if (np?.trackID, np?.artworkURL) != oldArt { onArtwork?(np?.trackID, np?.artworkURL) }

        if case .terminated = event {
            cancelFollowUp()
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

    /// Cancels any pending follow-up refresh. Call before dropping the coordinator.
    public func stop() { cancelFollowUp() }

    /// Spotify posts no broadcast for a same-track restart, so one late read refreshes the position anchor.
    /// Replaces any pending follow-up, so rapid clicks leave at most one.
    private func scheduleFollowUp() {
        guard model.availability != .notRunning else { return }
        followUp?.cancel()
        followUp = scheduler.schedule(after: Self.commandFollowUpDelay) { [weak self] in
            guard let self else { return }
            followUp = nil
            guard model.availability != .notRunning else { return }
            client.refresh()
        }
    }

    private func cancelFollowUp() {
        followUp?.cancel()
        followUp = nil
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
