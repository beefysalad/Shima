import Foundation
import Testing
@testable import ShimaCore

@Suite struct SpotifyReadingTests {
    let full: [AnyHashable: Any] = [
        "Player State": "Playing", "Track ID": "spotify:track:abc", "Name": "Song", "Artist": "Artist",
        "Album": "Album", "Duration": NSNumber(value: 200_000), "Playback Position": NSNumber(value: 71.5),
        "Has Artwork": true, "Popularity": NSNumber(value: 50)]

    @Test func parsesFullPayload() {
        #expect(SpotifyReading(notification: full) == SpotifyReading(
            state: .playing, trackID: "spotify:track:abc", title: "Song", artist: "Artist", album: "Album",
            duration: 200, position: 71.5, artworkURL: nil))
    }
    @Test func parsesStoppedOnly() {
        #expect(SpotifyReading(notification: ["Player State": "Stopped"]) == SpotifyReading(state: .stopped))
    }
    @Test func parsesPaused() { #expect(SpotifyReading(notification: ["Player State": "Paused"])?.state == .paused) }
    @Test func missingOrUnknownStateIsNil() {
        #expect(SpotifyReading(notification: [:]) == nil)
        #expect(SpotifyReading(notification: ["Player State": "Buffering"]) == nil)
    }
    @Test func emptyStringsAreMissing() {
        let r = SpotifyReading(notification: ["Player State": "Playing", "Track ID": "", "Name": "", "Artist": "", "Album": ""])
        #expect(r?.trackID == nil && r?.title == nil && r?.artist == nil && r?.album == nil)
    }
    @Test func displayFields() {
        #expect(SpotifyReading(notification: full)?.hasDisplayFields == true)
        #expect(!SpotifyReading(state: .playing, trackID: "x").hasDisplayFields)
        #expect(!SpotifyReading(state: .playing, title: "Song", artist: "Artist", position: 0).hasDisplayFields)
        #expect(!SpotifyReading(state: .playing, trackID: "x", artist: "Artist", position: 0).hasDisplayFields)
        #expect(!SpotifyReading(state: .playing, trackID: "x", title: "Song", position: 0).hasDisplayFields)
        #expect(!SpotifyReading(state: .playing, trackID: "x", title: "Song", artist: "Artist").hasDisplayFields)
    }
    @Test func artworkURLMustBeHTTPS() {
        #expect(SpotifyReading.artworkURL(from: "https://i.scdn.co/image/ab67616d0000b273")
            == URL(string: "https://i.scdn.co/image/ab67616d0000b273"))
        #expect(SpotifyReading.artworkURL(from: "http://example.com/a.jpg") == nil)
        #expect(SpotifyReading.artworkURL(from: "http://i.scdn.co/image/abc") == nil)
        #expect(SpotifyReading.artworkURL(from: "file:///tmp/a.jpg") == nil)
        #expect(SpotifyReading.artworkURL(from: "") == nil)
        #expect(SpotifyReading.artworkURL(from: nil) == nil)
    }
    @Test func sparseSameTrackPauseAndPlayPreserveOnlyPresentFields() {
        for (state, expected) in [("Paused", PlaybackState.paused), ("Playing", .playing)] {
            let reading = SpotifyReading(notification: [
                "Player State": state, "Track ID": "spotify:track:abc",
                "Duration": NSNumber(value: 187_146), "Playback Position": NSNumber(value: 119.158)])
            #expect(reading == SpotifyReading(state: expected, trackID: "spotify:track:abc", duration: 187.146, position: 119.158))
            #expect(reading?.hasDisplayFields == false)
        }
    }
    @Test func malformedOptionalFieldsAreIgnored() {
        let reading = SpotifyReading(notification: [
            "Player State": "Playing", "Track ID": 123, "Name": NSNull(), "Artist": ["Artist"],
            "Album": false, "Duration": "200000", "Playback Position": "71.5",
            "Artwork URL": "https://i.scdn.co/image/abc", "Has Artwork": true])
        #expect(reading == SpotifyReading(state: .playing))
    }
    @Test func malformedStateIsRejected() {
        for state: Any in [NSNumber(value: 1), NSNull(), ["Playing"], "playing", ""] {
            #expect(SpotifyReading(notification: ["Player State": state]) == nil)
        }
    }
    @Test func booleanNumbersAreNotTimes() {
        for value in [NSNumber(value: true), NSNumber(value: false)] {
            let reading = SpotifyReading(notification: ["Player State": "Playing", "Duration": value, "Playback Position": value])
            #expect(reading == SpotifyReading(state: .playing))
        }
    }
    @Test func invalidNumericFieldsAreMissing() {
        let invalid: [Double] = [.nan, .infinity, -.infinity, -1, .greatestFiniteMagnitude, Double(Int.max), Double(UInt64.max)]
        for value in invalid {
            let reading = SpotifyReading(notification: [
                "Player State": "Playing", "Duration": NSNumber(value: value), "Playback Position": NSNumber(value: value)])
            #expect(reading == SpotifyReading(state: .playing))
        }
    }
    @Test func numericBoundsAreInclusiveAndUnitsAreIndependent() {
        for seconds in [0.0, 0.125, 604_800] {
            let reading = SpotifyReading(notification: [
                "Player State": "Playing", "Duration": NSNumber(value: seconds * 1_000),
                "Playback Position": NSNumber(value: seconds)])
            #expect(reading?.duration == seconds)
            #expect(reading?.position == seconds)
            let formatted = PlaybackTime.elapsed(reading?.position ?? 0)
            #expect(!formatted.isEmpty)
        }
        #expect(SpotifyReading(notification: ["Player State": "Playing", "Duration": 604_800_001])?.duration == nil)
        #expect(SpotifyReading(notification: ["Player State": "Playing", "Playback Position": 604_800.001])?.position == nil)
        let reading = SpotifyReading(notification: ["Player State": "Paused", "Duration": 1_000, "Playback Position": 2.5])
        #expect(reading?.duration == 1 && reading?.position == 2.5)
    }
    @Test func invalidOptionalNumbersDoNotDiscardValidMetadata() {
        var payload = full
        payload["Duration"] = NSNumber(value: Double.nan)
        payload["Playback Position"] = NSNumber(value: Double.infinity)
        let reading = SpotifyReading(notification: payload)
        #expect(reading?.title == "Song" && reading?.trackID == "spotify:track:abc")
        #expect(reading?.duration == nil && reading?.position == nil)
        #expect(reading?.hasDisplayFields == false)
    }
    @Test func directInitializerRejectsUnsafeTimes() {
        for value: Double in [.nan, .infinity, -.infinity, -1, 604_800.001, Double(Int.max), .greatestFiniteMagnitude] {
            let reading = SpotifyReading(state: .playing, duration: value, position: value)
            #expect(reading.duration == nil && reading.position == nil)
        }
        let reading = SpotifyReading(state: .paused, duration: 604_800, position: 0)
        #expect(reading.duration == 604_800 && reading.position == 0)
    }
}
