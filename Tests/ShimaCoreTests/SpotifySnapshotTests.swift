import Foundation
import Testing
@testable import ShimaCore

private final class SnapshotFixture: SpotifySnapshotSource {
    var calls: [String] = []
    var state: PlaybackState = .paused
    var ids: [String?] = ["first", "first"]
    var metadata: [SpotifyTrackText: String] = [.title: "Song", .artist: "Artist", .album: "Album", .artwork: "https://i.scdn.co/image"]
    var duration: Int32 = 123456
    var failureAt: String?
    func record(_ name: String) throws {
        calls.append(name)
        if failureAt == name { throw SpotifyScriptError.timeout }
    }
    func playbackState() throws -> PlaybackState { try record("state"); return state }
    func position() throws -> TimeInterval { try record("position"); return 12.5 }
    func text(_ property: SpotifyTrackText) throws -> String? {
        try record(property.rawValue)
        return property == .id ? ids.removeFirst() : metadata[property]
    }
    func durationMilliseconds() throws -> Int32 { try record("duration"); return duration }
}

struct SpotifySnapshotTests {
    @Test func snapshotPreservesPropertyOrderAndDatesPositionBeforeMetadata() throws {
        let source = SnapshotFixture(), date = Date(timeIntervalSinceReferenceDate: 123)
        let snapshot = try SpotifySnapshot.read(from: source, now: { source.calls.append("date"); return date })
        #expect(snapshot.reading == SpotifyReading(state: .paused, trackID: "first", title: "Song", artist: "Artist", album: "Album",
                                                   duration: 123.456, position: 12.5, artworkURL: URL(string: "https://i.scdn.co/image")))
        #expect(snapshot.date == date && snapshot.consistent)
        #expect(source.calls == ["state", "position", "date", "ID  ", "pnam", "pArt", "pAlb", "duration", "aUrl", "ID  "])
    }

    @Test func stoppedSkipsAllTrackReadsAndDiscardsPosition() throws {
        let source = SnapshotFixture(); source.state = .stopped
        let snapshot = try SpotifySnapshot.read(from: source)
        #expect(snapshot.reading == SpotifyReading(state: .stopped) && snapshot.consistent)
        #expect(source.calls == ["state", "position"])
    }

    @Test(arguments: [[String?](arrayLiteral: "first", "second"), ["first", nil], [nil, nil]])
    func consistencyComparesBothTrackIDsAndUsesFinalID(ids: [String?]) throws {
        let source = SnapshotFixture(); source.ids = ids
        let snapshot = try SpotifySnapshot.read(from: source)
        #expect(snapshot.consistent == (ids[0] == ids[1]))
        #expect(snapshot.reading.trackID == ids[1])
    }

    @Test func missingMetadataAndInsecureArtworkStayMissing() throws {
        let source = SnapshotFixture(); source.ids = [nil, nil]
        source.metadata = [.artwork: "http://i.scdn.co/image"]
        source.duration = -1
        let snapshot = try SpotifySnapshot.read(from: source)
        #expect(snapshot.reading == SpotifyReading(state: .paused, position: 12.5))
    }

    @Test(arguments: ["state", "position", "pnam", "duration", "aUrl"])
    func readFailurePropagatesWithoutReturningPartialSnapshot(at: String) {
        let source = SnapshotFixture(); source.failureAt = at
        #expect(throws: SpotifyScriptError.timeout) { try SpotifySnapshot.read(from: source) }
        #expect(source.calls.last == at)
    }

    @Test(arguments: [-600, -609, -1743, -1712, -10000, 0, 42])
    func scriptErrorsRoundTripTheirDiagnosticCodes(code: Int) {
        #expect(SpotifyScriptError(code: code).code == code)
    }
}
