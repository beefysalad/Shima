import Foundation

public enum ReadingSource: Equatable, Sendable {
    case notification, script
}

public struct SpotifyReading: Equatable, Sendable {
    public var state: PlaybackState
    public var trackID: String?
    public var title: String?
    public var artist: String?
    public var album: String?
    public var duration: TimeInterval?
    public var position: TimeInterval?
    public var artworkURL: URL?

    public init(
        state: PlaybackState, trackID: String? = nil, title: String? = nil,
        artist: String? = nil, album: String? = nil, duration: TimeInterval? = nil,
        position: TimeInterval? = nil, artworkURL: URL? = nil
    ) {
        self.state = state
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
        self.artworkURL = artworkURL
    }
}
