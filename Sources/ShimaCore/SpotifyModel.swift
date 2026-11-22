import Foundation

public enum SpotifyAvailability: Equatable, Sendable {
    case notRunning, running, permissionDenied
}

public enum SpotifyEvent: Equatable, Sendable {
    case launched, terminated, permissionDenied
    /// A user command was accepted by Spotify. Carries no playback data; it only owes a late refresh.
    case commandSucceeded(SpotifyCommand)
    case reading(SpotifyReading, source: ReadingSource, at: Date)
    /// A script refresh failed without a permission error (timeout, Spotify gone). Carries no data.
    case refreshFailed
}

public enum SpotifyChange: Equatable, Sendable {
    case availabilityChanged(SpotifyAvailability)
    case trackChanged(id: String?)
    case stateChanged(PlaybackState?)
}

public enum NowPlayingContent: Equatable, Sendable {
    case notRunning, permissionDenied, nothingPlaying, track

    public init(availability: SpotifyAvailability, nowPlaying: NowPlaying?) {
        switch availability {
        case .notRunning: self = .notRunning
        case .permissionDenied: self = .permissionDenied
        case .running: self = nowPlaying == nil ? .nothingPlaying : .track
        }
    }
}

public struct SpotifyModel: Equatable, Sendable {
    public private(set) var availability: SpotifyAvailability = .notRunning
    public private(set) var nowPlaying: NowPlaying?

    public init() {}

    public var isLive: Bool {
        availability != .notRunning && nowPlaying?.state == .playing
    }

    public var content: NowPlayingContent {
        NowPlayingContent(availability: availability, nowPlaying: nowPlaying)
    }

    public mutating func apply(_ event: SpotifyEvent) -> (NowPlaying?, [SpotifyChange]) {
        var changes: [SpotifyChange] = []
        switch event {
        case .launched:
            if availability == .notRunning {
                availability = .running
                changes.append(.availabilityChanged(.running))
            }
        case .terminated:
            if availability != .notRunning {
                changes.append(.availabilityChanged(.notRunning))
            }
            availability = .notRunning
            clearTrack(changes: &changes)
        case .commandSucceeded, .refreshFailed: break
        case .permissionDenied:
            if availability == .running {
                availability = .permissionDenied
                changes.append(.availabilityChanged(.permissionDenied))
            }
        case let .reading(reading, source, at):
            guard availability != .notRunning else { return (nowPlaying, []) }
            if availability == .permissionDenied && source == .script {
                availability = .running
                changes.append(.availabilityChanged(.running))
            }
            guard reading.state != .stopped, let trackID = reading.trackID else {
                clearTrack(changes: &changes)
                return (nowPlaying, changes)
            }
            let oldState = nowPlaying?.state
            if var current = nowPlaying, current.trackID == trackID {
                let old = current
                current.title = reading.title ?? current.title
                current.artist = reading.artist ?? current.artist
                current.album = reading.album ?? current.album
                current.duration = reading.duration ?? current.duration
                current.artworkURL = reading.artworkURL ?? current.artworkURL
                if let position = reading.position {
                    current.position = position
                    current.positionDate = at
                } else if oldState != reading.state {
                    // Freeze or resume from the position projected with the old state and duration.
                    current.position = old.position(at: at)
                    current.positionDate = at
                }
                current.state = reading.state
                nowPlaying = current
            } else {
                nowPlaying = NowPlaying(
                    trackID: trackID, title: reading.title ?? "", artist: reading.artist ?? "",
                    album: reading.album ?? "", artworkURL: reading.artworkURL,
                    duration: reading.duration ?? 0, position: reading.position ?? 0,
                    positionDate: at, state: reading.state
                )
                changes.append(.trackChanged(id: trackID))
            }
            if oldState != reading.state {
                changes.append(.stateChanged(reading.state))
            }
        }
        return (nowPlaying, changes)
    }

    /// Applies a late follow-up reading: only the position anchor of the same track may change.
    /// State, identity and metadata are left to the broadcasts, which are more reliable than the script state.
    /// Outside `.running` this is the normal reducer, so availability transitions are never swallowed.
    public mutating func applyPositionOnly(_ reading: SpotifyReading, at: Date) -> (NowPlaying?, [SpotifyChange]) {
        guard availability == .running else { return apply(.reading(reading, source: .script, at: at)) }
        guard var current = nowPlaying, current.trackID == reading.trackID, let position = reading.position else {
            return (nowPlaying, [])
        }
        current.position = position
        current.positionDate = at
        nowPlaying = current
        return (current, [])
    }

    private mutating func clearTrack(changes: inout [SpotifyChange]) {
        if nowPlaying != nil {
            nowPlaying = nil
            changes.append(.trackChanged(id: nil))
            changes.append(.stateChanged(nil))
        }
    }
}
