import Foundation

public enum SpotifyTrackText: String, Sendable {
    case id = "ID  ", title = "pnam", artist = "pArt", album = "pAlb", artwork = "aUrl"
}

/// A synchronous property source. The app supplies Apple Event values on its private queue.
public protocol SpotifySnapshotSource {
    func playbackState() throws -> PlaybackState
    func position() throws -> TimeInterval
    func text(_ property: SpotifyTrackText) throws -> String?
    func durationMilliseconds() throws -> Int32
}

public struct SpotifySnapshot: Equatable, Sendable {
    public let reading: SpotifyReading
    public let date: Date
    public let consistent: Bool

    public static func read(from source: any SpotifySnapshotSource, now: () -> Date = { Date() }) throws -> Self {
        let state = try source.playbackState()
        let position = try source.position()
        let date = now()
        if state == .stopped { return Self(reading: SpotifyReading(state: .stopped), date: date, consistent: true) }

        let firstID = try source.text(.id)
        let title = try source.text(.title)
        let artist = try source.text(.artist)
        let album = try source.text(.album)
        let durationMs = try source.durationMilliseconds()
        let artwork = try source.text(.artwork)
        let trackID = try source.text(.id)
        let consistent = SpotifySnapshotConsistency.isConsistent(firstTrackID: firstID, lastTrackID: trackID)
        let reading = SpotifyReading(
            state: state, trackID: trackID, title: title, artist: artist, album: album,
            duration: TimeInterval(durationMs) / 1000, position: position,
            artworkURL: SpotifyReading.artworkURL(from: artwork))
        return Self(reading: reading, date: date, consistent: consistent)
    }
}
