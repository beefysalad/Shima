import Foundation
import CoreFoundation

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
        self.duration = Self.validSeconds(duration)
        self.position = Self.validSeconds(position)
        self.artworkURL = artworkURL
    }

    /// Parses the fields present in a PlaybackStateChanged broadcast.
    /// Same-track pause/play broadcasts omit title, artist and album.
    public init?(notification userInfo: [AnyHashable: Any]) {
        let state: PlaybackState
        switch userInfo["Player State"] as? String {
        case "Playing": state = .playing
        case "Paused": state = .paused
        case "Stopped": state = .stopped
        default: return nil
        }
        self.init(
            state: state,
            trackID: Self.nonemptyString(userInfo["Track ID"]),
            title: Self.nonemptyString(userInfo["Name"]),
            artist: Self.nonemptyString(userInfo["Artist"]),
            album: Self.nonemptyString(userInfo["Album"]),
            duration: Self.seconds(from: userInfo["Duration"], unitsPerSecond: 1_000),
            position: Self.seconds(from: userInfo["Playback Position"], unitsPerSecond: 1)
        )
    }

    public static func artworkURL(from string: String?) -> URL? {
        guard let string, !string.isEmpty,
              let url = URL(string: string), url.scheme?.lowercased() == "https"
        else { return nil }
        return url
    }

    public var hasDisplayFields: Bool {
        trackID != nil && title != nil && artist != nil && position != nil
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    // A seven-day inclusive limit keeps malformed times far below Int conversion
    // limits while allowing long recordings. Invalid optional times are missing.
    private static let maximumSeconds: TimeInterval = 604_800

    private static func validSeconds(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value.isFinite, value >= 0, value <= maximumSeconds else { return nil }
        return value
    }

    private static func seconds(from value: Any?, unitsPerSecond: Double) -> TimeInterval? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let raw = number.doubleValue
        // Validate before converting milliseconds: dividing must not disguise an
        // out-of-Int-range input. Double(Int.max) rounds upward, so use strict <.
        guard raw.isFinite, raw >= 0, raw < Double(Int.max),
              raw <= maximumSeconds * unitsPerSecond else { return nil }
        return validSeconds(raw / unitsPerSecond)
    }
}
