import Foundation
import Testing
@testable import ShimaCore

@Suite struct SpotifyModelTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    let art = URL(string: "https://i.scdn.co/image/a")!
    func reading(_ state: PlaybackState, _ id: String? = "spotify:track:a", position: TimeInterval? = 10, art: URL? = nil) -> SpotifyReading {
        SpotifyReading(state: state, trackID: id, title: "Song", artist: "Artist", album: "Album",
                       duration: 200, position: position, artworkURL: art)
    }
    func running() -> SpotifyModel { var m = SpotifyModel(); _ = m.apply(.launched); return m }

    @Test func launchMakesRunning() {
        var m = SpotifyModel()
        let (np, changes) = m.apply(.launched)
        #expect(np == nil && changes == [.availabilityChanged(.running)])
        #expect(m.availability == .running && !m.isLive && m.content == .nothingPlaying)
    }
    @Test func secondLaunchChangesNothing() { var m = running(); #expect(m.apply(.launched).1 == []) }
    @Test func readingWhileNotRunningIsIgnored() {
        var m = SpotifyModel()
        let (np, changes) = m.apply(.reading(reading(.playing), source: .notification, at: t0))
        #expect(np == nil && changes == [] && m.availability == .notRunning && m.content == .notRunning)
    }
    @Test func playingNotificationStartsTrack() {
        var m = running()
        let (np, changes) = m.apply(.reading(reading(.playing), source: .notification, at: t0))
        #expect(np == NowPlaying(trackID: "spotify:track:a", title: "Song", artist: "Artist", album: "Album",
            artworkURL: nil, duration: 200, position: 10, positionDate: t0, state: .playing))
        #expect(changes == [.trackChanged(id: "spotify:track:a"), .stateChanged(.playing)])
        #expect(m.isLive && m.content == .track)
    }
    @Test func sameTrackKeepsArtworkAndUpdatesState() {
        var m = running()
        _ = m.apply(.reading(reading(.playing, art: art), source: .script, at: t0))
        let (np, changes) = m.apply(.reading(reading(.paused, position: 15), source: .notification, at: t0 + 5))
        #expect(np?.artworkURL == art && np?.state == .paused && np?.position == 15 && np?.positionDate == t0 + 5)
        #expect(changes == [.stateChanged(.paused)] && !m.isLive)
    }
    @Test func pauseWithoutPositionFreezesExtrapolatedPosition() {
        var m = running()
        _ = m.apply(.reading(reading(.playing), source: .notification, at: t0))
        let (np, _) = m.apply(.reading(reading(.paused, position: nil), source: .notification, at: t0 + 4))
        #expect(np?.position == 14 && np?.positionDate == t0 + 4)
    }
    @Test func newTrackDropsOldArtwork() {
        var m = running()
        _ = m.apply(.reading(reading(.playing, art: art), source: .script, at: t0))
        let (np, changes) = m.apply(.reading(reading(.playing, "spotify:track:b"), source: .notification, at: t0 + 1))
        #expect(np?.trackID == "spotify:track:b" && np?.artworkURL == nil)
        #expect(changes == [.trackChanged(id: "spotify:track:b")])
    }
    @Test func stoppedClearsNowPlaying() {
        var m = running()
        _ = m.apply(.reading(reading(.playing), source: .notification, at: t0))
        let (np, changes) = m.apply(.reading(SpotifyReading(state: .stopped), source: .notification, at: t0 + 1))
        #expect(np == nil && changes == [.trackChanged(id: nil), .stateChanged(nil)] && !m.isLive)
    }
    @Test func terminatedClearsEverything() {
        var m = running()
        _ = m.apply(.reading(reading(.playing), source: .notification, at: t0))
        let (np, changes) = m.apply(.terminated)
        #expect(np == nil && changes == [.availabilityChanged(.notRunning), .trackChanged(id: nil), .stateChanged(nil)])
        #expect(!m.isLive && m.content == .notRunning)
    }
    @Test func missingTrackIDIsNoTrack() {
        var m = running()
        let (np, changes) = m.apply(.reading(reading(.playing, nil), source: .notification, at: t0))
        #expect(np == nil && changes == [])
    }
    @Test func permissionDeniedUntilAScriptReadingSucceeds() {
        var m = running()
        #expect(m.apply(.permissionDenied).1 == [.availabilityChanged(.permissionDenied)])
        #expect(m.content == .permissionDenied)
        _ = m.apply(.reading(reading(.playing), source: .notification, at: t0))
        #expect(m.availability == .permissionDenied && m.isLive)
        let (_, changes) = m.apply(.reading(reading(.playing), source: .script, at: t0 + 1))
        #expect(changes == [.availabilityChanged(.running)] && m.content == .track)
    }
    @Test func permissionDeniedWhileNotRunningIsIgnored() {
        var m = SpotifyModel()
        #expect(m.apply(.permissionDenied).1 == [] && m.availability == .notRunning)
    }
    @Test func sparseSameTrackPreservesMetadataAndPositionAnchor() {
        var m = running()
        _ = m.apply(.reading(reading(.playing, art: art), source: .script, at: t0))
        let previous = m.nowPlaying
        let (np, changes) = m.apply(.reading(
            SpotifyReading(state: .playing, trackID: "spotify:track:a"), source: .notification, at: t0 + 5))
        #expect(np == previous && changes == [])
    }
    @Test func sameTrackReplacesEveryProvidedFieldIncludingEmptyAndZero() {
        var m = running()
        _ = m.apply(.reading(reading(.playing, art: art), source: .script, at: t0))
        let replacementArt = URL(string: "https://i.scdn.co/image/b")!
        let replacement = SpotifyReading(state: .playing, trackID: "spotify:track:a",
            title: "", artist: "New artist", album: "New album", duration: 0, position: 0, artworkURL: replacementArt)
        let (np, changes) = m.apply(.reading(replacement, source: .script, at: t0 + 2))
        #expect(np == NowPlaying(trackID: "spotify:track:a", title: "", artist: "New artist",
            album: "New album", artworkURL: replacementArt, duration: 0, position: 0, positionDate: t0 + 2, state: .playing))
        #expect(changes == [])
    }
    @Test func resumeWithoutPositionKeepsPausedPosition() {
        var m = running()
        _ = m.apply(.reading(reading(.paused), source: .script, at: t0))
        let (np, changes) = m.apply(.reading(reading(.playing, position: nil), source: .script, at: t0 + 20))
        #expect(np?.position == 10 && np?.positionDate == t0 + 20)
        #expect(changes == [.stateChanged(.playing)])
    }
    @Test func pauseProjectsUsingOldDurationBeforeMergingNewDuration() {
        var m = running()
        _ = m.apply(.reading(reading(.playing), source: .script, at: t0))
        let (np, _) = m.apply(.reading(SpotifyReading(state: .paused,
            trackID: "spotify:track:a", duration: 5), source: .script, at: t0 + 4))
        #expect(np?.position == 14 && np?.duration == 5)
    }
    @Test func sparseNewTrackUsesDefaultsAndEmitsStateChange() {
        var m = running()
        _ = m.apply(.reading(reading(.playing, art: art), source: .script, at: t0))
        let (np, changes) = m.apply(.reading(SpotifyReading(state: .paused, trackID: "b"), source: .script, at: t0 + 1))
        #expect(np == NowPlaying(trackID: "b", title: "", artist: "", album: "", artworkURL: nil,
            duration: 0, position: 0, positionDate: t0 + 1, state: .paused))
        #expect(changes == [.trackChanged(id: "b"), .stateChanged(.paused)])
    }
    @Test(arguments: [false, true]) func scriptRecoveryOrdersAvailabilityBeforeClear(hasTrack: Bool) {
        var m = running()
        if hasTrack { _ = m.apply(.reading(reading(.playing), source: .script, at: t0)) }
        _ = m.apply(.permissionDenied)
        let (np, changes) = m.apply(.reading(SpotifyReading(state: .stopped), source: .script, at: t0 + 1))
        let expected: [SpotifyChange] = hasTrack
            ? [.availabilityChanged(.running), .trackChanged(id: nil), .stateChanged(nil)]
            : [.availabilityChanged(.running)]
        #expect(np == nil && changes == expected && m.content == .nothingPlaying)
    }
    @Test func permissionDeniedNoOpsAndTerminationWithoutTrack() {
        var m = running()
        _ = m.apply(.permissionDenied)
        #expect(m.apply(.permissionDenied).1 == [])
        #expect(m.apply(.launched).1 == [] && m.availability == .permissionDenied)
        #expect(m.apply(.terminated).1 == [.availabilityChanged(.notRunning)])
        #expect(m.apply(.terminated).1 == [])
    }
    @Test func missingIDClearsExistingTrackAndRepeatedStopIsNoOp() {
        var m = running()
        _ = m.apply(.reading(reading(.playing), source: .script, at: t0))
        let (np, changes) = m.apply(.reading(reading(.playing, nil), source: .notification, at: t0 + 1))
        #expect(np == nil && changes == [.trackChanged(id: nil), .stateChanged(nil)])
        #expect(m.apply(.reading(SpotifyReading(state: .stopped), source: .notification, at: t0 + 2)).1 == [])
    }
    @Test func recoveryWithNewTrackOrdersAllChanges() {
        var m = running()
        _ = m.apply(.permissionDenied)
        let (_, changes) = m.apply(.reading(reading(.playing), source: .script, at: t0))
        #expect(changes == [.availabilityChanged(.running), .trackChanged(id: "spotify:track:a"), .stateChanged(.playing)])
    }
    @Test func contentKinds() {
        let np = NowPlaying(trackID: "a", title: "", artist: "", album: "", artworkURL: nil,
                            duration: 0, position: 0, positionDate: t0, state: .paused)
        #expect(NowPlayingContent(availability: .notRunning, nowPlaying: np) == .notRunning)
        #expect(NowPlayingContent(availability: .permissionDenied, nowPlaying: np) == .permissionDenied)
        #expect(NowPlayingContent(availability: .running, nowPlaying: nil) == .nothingPlaying)
        #expect(NowPlayingContent(availability: .running, nowPlaying: np) == .track)
    }
}
