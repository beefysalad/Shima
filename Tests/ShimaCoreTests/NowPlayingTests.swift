import Foundation
import Testing
@testable import ShimaCore

@Suite struct NowPlayingTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    func track(_ state: PlaybackState, position: TimeInterval = 10, duration: TimeInterval = 200) -> NowPlaying {
        NowPlaying(trackID: "spotify:track:a", title: "Song", artist: "Artist", album: "Album",
                   artworkURL: nil, duration: duration, position: position, positionDate: t0, state: state)
    }

    @Test func playingExtrapolates() { #expect(track(.playing).position(at: t0 + 5) == 15) }
    @Test func playingClampsToDuration() { #expect(track(.playing, position: 198).position(at: t0 + 30) == 200) }
    @Test func pausedIsStatic() { #expect(track(.paused).position(at: t0 + 30) == 10) }
    @Test func clockBeforeSampleNeverGoesBack() { #expect(track(.playing).position(at: t0 - 5) == 10) }
    @Test func unknownDurationHasNoUpperClamp() { #expect(track(.playing, duration: 0).position(at: t0 + 500) == 510) }
    @Test func elapsedFormat() {
        #expect(PlaybackTime.elapsed(0) == "0:00")
        #expect(PlaybackTime.elapsed(71.9) == "1:11")
        #expect(PlaybackTime.elapsed(3725) == "1:02:05")
        #expect(PlaybackTime.elapsed(-3) == "0:00")
    }
    @Test func remainingFormat() {
        #expect(PlaybackTime.remaining(position: 71, duration: 200) == "-2:09")
        #expect(PlaybackTime.remaining(position: 250, duration: 200) == "-0:00")
    }
    @Test func unknownDurationShowsNoRemaining() { #expect(PlaybackTime.remaining(position: 10, duration: 0) == "") }
    @Test func fraction() {
        #expect(PlaybackTime.fraction(position: 71, duration: 200) == 0.355)
        #expect(PlaybackTime.fraction(position: 10, duration: 0) == 0)
        #expect(PlaybackTime.fraction(position: 300, duration: 200) == 1)
    }
    @Test func stoppedIsStatic() { #expect(track(.stopped).position(at: t0 + 30) == 10) }
    @Test func negativePositionsNeverGoBelowZero() {
        #expect(track(.playing, position: -10).position(at: t0 + 5) == 0)
        #expect(track(.paused, position: -10).position(at: t0 + 30) == 0)
        #expect(track(.stopped, position: -10).position(at: t0 + 30) == 0)
    }
    @Test func fractionalBoundariesFloorSeparately() {
        #expect(PlaybackTime.elapsed(59.99) == "0:59")
        #expect(PlaybackTime.elapsed(60) == "1:00")
        #expect(PlaybackTime.remaining(position: 71.9, duration: 200.1) == "-2:09")
        #expect(PlaybackTime.remaining(position: 199.9, duration: 200) == "-0:01")
    }
    @Test func nonpositiveDurationAndNegativeFraction() {
        #expect(PlaybackTime.remaining(position: 10, duration: -1) == "")
        #expect(PlaybackTime.fraction(position: 10, duration: -1) == 0)
        #expect(PlaybackTime.fraction(position: -10, duration: 200) == 0)
    }
}
