import Foundation

public enum PlaybackState: String, Equatable, Sendable {
    case playing, paused, stopped
}

public enum SpotifyCommand: String, Equatable, Sendable, CaseIterable {
    case previous, playPause, next
}

public struct NowPlaying: Equatable, Sendable {
    public var trackID: String
    public var title: String
    public var artist: String
    public var album: String
    public var artworkURL: URL?
    public var duration: TimeInterval
    public var position: TimeInterval
    public var positionDate: Date
    public var state: PlaybackState

    public init(
        trackID: String, title: String, artist: String, album: String,
        artworkURL: URL?, duration: TimeInterval, position: TimeInterval,
        positionDate: Date, state: PlaybackState
    ) {
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.duration = duration
        self.position = position
        self.positionDate = positionDate
        self.state = state
    }

    public func position(at date: Date) -> TimeInterval {
        guard state == .playing else { return max(0, position) }
        let extrapolated = position + max(0, date.timeIntervalSince(positionDate))
        return max(0, duration > 0 ? min(extrapolated, duration) : extrapolated)
    }
}

public enum PlaybackTime {
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let wholeSeconds = Int(max(0, seconds).rounded(.down))
        let secondsPart = String(format: "%02d", wholeSeconds % 60)
        if wholeSeconds >= 3_600 {
            let minutesPart = String(format: "%02d", wholeSeconds / 60 % 60)
            return "\(wholeSeconds / 3_600):\(minutesPart):\(secondsPart)"
        }
        return "\(wholeSeconds / 60):\(secondsPart)"
    }

    public static func remaining(position: TimeInterval, duration: TimeInterval) -> String {
        guard duration > 0 else { return "" }
        return "-" + elapsed(max(0, duration.rounded(.down) - position.rounded(.down)))
    }

    public static func fraction(position: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, position / duration))
    }
}
