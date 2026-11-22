import Foundation

@MainActor public final class FakeSpotifyClient: SpotifyClient {
    public static let tracks: [(id: String, title: String, duration: TimeInterval)] = [
        ("fake:1", "Fake Track One", 200),
        ("fake:2", "Fake Track Two", 180),
        ("fake:3", "Fake Track Three", 240)
    ]

    public var onEvent: (@MainActor (SpotifyEvent) -> Void)?
    public private(set) var refreshCount = 0
    public private(set) var sent: [SpotifyCommand] = []
    private let now: @MainActor () -> Date
    private var state: PlaybackState
    private var trackIndex = 0
    private var position: TimeInterval = 0
    private var positionDate: Date

    public init(state: PlaybackState, now: @escaping @MainActor () -> Date = { Date() }) {
        self.state = state
        self.now = now
        self.positionDate = now()
    }

    public func refresh() {
        refreshCount += 1
        emit(source: .script, at: now())
    }

    public func send(_ command: SpotifyCommand) {
        sent.append(command)
        let date = now()
        switch command {
        case .previous:
            trackIndex = (trackIndex + Self.tracks.count - 1) % Self.tracks.count
            position = 0
        case .next:
            trackIndex = (trackIndex + 1) % Self.tracks.count
            position = 0
        case .playPause:
            position = position(at: date)
            state = state == .playing ? .paused : .playing
        }
        positionDate = date
        emit(source: .notification, at: date)
    }

    public func setState(_ state: PlaybackState) {
        let date = now()
        position = position(at: date)
        positionDate = date
        self.state = state
        emit(source: .notification, at: date)
    }

    public func invalidate() {}

    private func position(at date: Date) -> TimeInterval {
        let elapsed = state == .playing ? max(0, date.timeIntervalSince(positionDate)) : 0
        return min(Self.tracks[trackIndex].duration, max(0, position + elapsed))
    }

    private func emit(source: ReadingSource, at date: Date) {
        let track = Self.tracks[trackIndex]
        let reading = SpotifyReading(
            state: state, trackID: track.id, title: track.title, artist: "shima fake",
            album: "Fixture", duration: track.duration, position: position(at: date), artworkURL: nil
        )
        onEvent?(.reading(reading, source: source, at: date))
    }
}

public enum FakeSpotifyMode {
    public static func initialState(_ value: String?) -> PlaybackState? {
        guard let value, !value.isEmpty else { return nil }
        return value == "playing" ? .playing : .paused
    }
}
