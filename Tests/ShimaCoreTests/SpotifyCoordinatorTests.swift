import Foundation
import Testing
@testable import ShimaCore

@MainActor final class TestClient: SpotifyClient {
    var onEvent: (@MainActor (SpotifyEvent) -> Void)?
    var refreshes = 0, invalidations = 0
    var sent: [SpotifyCommand] = []
    var duringRefresh: (@MainActor () -> Void)?
    var duringInvalidate: (@MainActor () -> Void)?
    func refresh() { refreshes += 1; duringRefresh?() }
    func send(_ command: SpotifyCommand) { sent.append(command) }
    func invalidate() { invalidations += 1; duringInvalidate?() }
}

struct ArtworkTap: Equatable { let id: String?; let url: URL? }

@MainActor final class Taps {
    var lives: [Bool] = []
    var changes: [[SpotifyChange]] = []
    var artworks: [ArtworkTap] = []
}

@Suite @MainActor struct SpotifyCoordinatorTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    let art = URL(string: "https://i.scdn.co/image/a")!

    func make() -> (SpotifyCoordinator, TestClient, AppState, Taps) {
        let client = TestClient(), state = AppState(), taps = Taps()
        let c = SpotifyCoordinator(client: client, state: state)
        c.onLiveChange = { taps.lives.append($0) }
        c.onChanges = { taps.changes.append($0) }
        c.onArtwork = { taps.artworks.append(ArtworkTap(id: $0, url: $1)) }
        return (c, client, state, taps)
    }
    func note(_ s: PlaybackState = .playing, _ id: String = "a") -> SpotifyEvent {
        .reading(SpotifyReading(state: s, trackID: id, title: "T", artist: "A", album: "L", duration: 200, position: 1),
                 source: .notification, at: t0)
    }
    func script(_ id: String = "a", art: URL?) -> SpotifyEvent {
        .reading(SpotifyReading(state: .playing, trackID: id, title: "T", artist: "A", album: "L", duration: 200,
                                position: 1, artworkURL: art), source: .script, at: t0)
    }

    @Test func launchSendsNoAppleEvents() {
        let (c, client, state, _) = make()
        c.handle(.launched)
        #expect(client.refreshes == 0 && client.sent == [] && state.spotifyAvailability == .running)
    }
    @Test func playingNotificationGoesLiveOnce() {
        let (c, _, state, taps) = make()
        c.handle(.launched); c.handle(note()); c.handle(note())
        #expect(taps.lives == [true] && state.nowPlaying?.trackID == "a" && state.content == .track)
    }
    @Test func pauseEndsLive() {
        let (c, _, _, taps) = make()
        c.handle(.launched); c.handle(note()); c.handle(note(.paused))
        #expect(taps.lives == [true, false])
    }
    @Test func terminateClearsStateAndInvalidatesClient() {
        let (c, client, state, taps) = make()
        c.handle(.launched); c.handle(note()); c.handle(.terminated)
        #expect(taps.lives == [true, false] && state.nowPlaying == nil)
        #expect(state.spotifyAvailability == .notRunning && client.invalidations == 1)
    }
    @Test func readingAfterTerminateIsIgnored() {
        let (c, client, state, taps) = make()
        c.handle(.launched); c.handle(.terminated); c.handle(note())
        #expect(state.nowPlaying == nil && taps.lives == [] && client.refreshes == 0)
    }
    @Test func missingArtworkRefreshesOncePerTrack() {
        let (c, client, _, _) = make()
        c.handle(.launched); c.handle(note(.playing, "a")); c.handle(note(.playing, "a")); c.handle(note(.playing, "b"))
        #expect(client.refreshes == 2)
    }
    @Test func knownArtworkDoesNotRefresh() {
        let (c, client, _, _) = make()
        c.handle(.launched); c.handle(note()); c.handle(script(art: art)); c.handle(note())
        #expect(client.refreshes == 1)
    }
    @Test func incompleteNotificationRefreshesEachTime() {
        let (c, client, _, _) = make()
        let bare = SpotifyEvent.reading(SpotifyReading(state: .playing, trackID: "a"), source: .notification, at: t0)
        c.handle(.launched); c.handle(bare); c.handle(bare)
        #expect(client.refreshes == 2)
    }
    @Test func scriptReadingNeverTriggersRefresh() {
        let (c, client, _, _) = make()
        c.handle(.launched); c.handle(script(art: nil))
        #expect(client.refreshes == 0)
    }
    @Test func islandOpenRefreshesOnlyWhenRunning() {
        let (c, client, _, _) = make()
        c.islandOpened()
        #expect(client.refreshes == 0)
        c.handle(.launched); c.islandOpened()
        #expect(client.refreshes == 1)
    }
    @Test func commandsOnlyWhenRunning() {
        let (c, client, _, _) = make()
        c.perform(.next)
        #expect(client.sent == [])
        c.handle(.launched); c.perform(.next)
        #expect(client.sent == [.next])
    }
    @Test func permissionDeniedRetriesOnlyOnNotificationOrOpen() {
        let (c, client, state, _) = make()
        c.handle(.launched); c.handle(.permissionDenied); c.perform(.playPause)
        #expect(client.sent == [] && client.refreshes == 0 && state.content == .permissionDenied)
        c.handle(note()); c.handle(note())
        #expect(client.refreshes == 2)
        c.islandOpened()
        #expect(client.refreshes == 3)
    }
    @Test func changesAreForwardedForTheBus() {
        let (c, _, _, taps) = make()
        c.handle(.launched); c.handle(note())
        #expect(taps.changes == [[.availabilityChanged(.running)], [.trackChanged(id: "a"), .stateChanged(.playing)]])
    }
    @Test func artworkCallbackFollowsTrackAndURL() {
        let (c, _, _, taps) = make()
        c.handle(.launched); c.handle(note(.playing, "a")); c.handle(script("a", art: art)); c.handle(note(.playing, "a")); c.handle(note(.playing, "b"))
        #expect(taps.artworks == [ArtworkTap(id: "a", url: nil), ArtworkTap(id: "a", url: art), ArtworkTap(id: "b", url: nil)])
    }
    @Test func fakeModeValues() {
        #expect(FakeSpotifyMode.initialState(nil) == nil)
        #expect(FakeSpotifyMode.initialState("") == nil)
        #expect(FakeSpotifyMode.initialState("playing") == .playing)
        #expect(FakeSpotifyMode.initialState("paused") == .paused)
        #expect(FakeSpotifyMode.initialState("1") == .paused)
    }
    @Test func appStateSpotifyDefaults() {
        let s = AppState()
        #expect(!s.live && s.nowPlaying == nil && s.spotifyAvailability == .notRunning && s.content == .notRunning)
    }
}

@MainActor final class EventBox { var events: [SpotifyEvent] = [] }

@Suite @MainActor struct FakeSpotifyClientTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    func reading(_ e: SpotifyEvent?) -> (SpotifyReading, ReadingSource)? {
        if case .reading(let r, let s, _)? = e { return (r, s) } else { return nil }
    }
    @Test func refreshReportsTheFixture() {
        let fake = FakeSpotifyClient(state: .playing, now: { self.t0 }), box = EventBox()
        fake.onEvent = { box.events.append($0) }
        fake.refresh()
        let r = reading(box.events.last)
        #expect(fake.refreshCount == 1 && r?.1 == .script)
        #expect(r?.0.trackID == "fake:1" && r?.0.state == .playing && r?.0.artworkURL == nil && r?.0.hasDisplayFields == true)
    }
    @Test func commandsActLikeSpotify() {
        let fake = FakeSpotifyClient(state: .playing, now: { self.t0 }), box = EventBox()
        fake.onEvent = { box.events.append($0) }
        fake.send(.next)
        #expect(reading(box.events.last)?.0.trackID == "fake:2" && reading(box.events.last)?.1 == .notification)
        fake.send(.playPause)
        #expect(reading(box.events.last)?.0.state == .paused)
        fake.send(.previous)
        #expect(reading(box.events.last)?.0.trackID == "fake:1")
        #expect(fake.sent == [.next, .playPause, .previous])
    }
}

@MainActor final class FakeClock {
    var date = Date(timeIntervalSinceReferenceDate: 1_000)
    func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
}

extension SpotifyCoordinatorTests {
    @Test func initializerPreservesOwnerEventHandler() {
        let client = TestClient(), box = EventBox()
        client.onEvent = { box.events.append($0) }
        let coordinator = SpotifyCoordinator(client: client, state: AppState())
        client.onEvent?(.launched)
        #expect(box.events == [.launched])
        #expect(coordinator.model.availability == .notRunning)
    }

    @Test func sparsePausePlayKeepsMetadataAndRefreshesWithKnownArtwork() {
        let (c, client, state, _) = make()
        c.handle(.launched); c.handle(script(art: art))
        for playback in [PlaybackState.paused, .playing] {
            c.handle(.reading(SpotifyReading(state: playback, trackID: "a", duration: 200, position: 12), source: .notification, at: t0))
            #expect(state.nowPlaying?.title == "T" && state.nowPlaying?.artist == "A")
            #expect(state.nowPlaying?.album == "L" && state.nowPlaying?.artworkURL == art)
        }
        #expect(client.refreshes == 2)
    }

    @Test func positionUpdateIsAppliedWhileCollapsed() {
        let (c, _, state, _) = make()
        c.handle(.launched); c.handle(script(art: art))
        let later = t0.addingTimeInterval(10)
        c.handle(.reading(SpotifyReading(state: .playing, trackID: "a", title: "T", artist: "A", position: 20), source: .notification, at: later))
        #expect(state.mode == .collapsed && state.nowPlaying?.position == 20)
        #expect(state.nowPlaying?.positionDate == later)
    }

    @Test func callbacksPrecedeSynchronousRefreshAndStateRemainsNewest() {
        let (c, client, state, _) = make()
        var order: [String] = []
        c.handle(.launched)
        c.onChanges = { _ in
            #expect(state.nowPlaying?.trackID == "a")
            order.append("changes")
        }
        c.onLiveChange = { _ in order.append("live") }
        c.onArtwork = { _, url in order.append(url == nil ? "art:nil" : "art:url") }
        client.duringRefresh = {
            order.append("refresh")
            c.handle(self.script(art: self.art))
        }
        c.handle(note())
        #expect(order == ["changes", "live", "art:nil", "refresh", "art:url"])
        #expect(state.nowPlaying?.artworkURL == art && client.refreshes == 1)
    }

    @Test func artworkRequestIsRememberedBeforeRefreshReentry() {
        let (c, client, _, _) = make()
        c.handle(.launched)
        client.duringRefresh = {
            if client.refreshes == 1 { c.handle(self.note()) }
        }
        c.handle(note())
        #expect(client.refreshes == 1)
        c.handle(.terminated); c.handle(.launched); c.handle(note())
        #expect(client.refreshes == 2)
    }

    @Test func stoppedBeforeTerminateClearsOnceThenInvalidatesAfterCallbacks() {
        let (c, client, state, taps) = make()
        c.handle(.launched); c.handle(note())
        c.handle(.reading(SpotifyReading(state: .stopped), source: .notification, at: t0))
        #expect(state.content == .nothingPlaying && state.nowPlaying == nil)
        #expect(taps.lives == [true, false] && client.refreshes == 2)
        var order: [String] = []
        c.onChanges = { _ in
            #expect(state.content == .notRunning)
            order.append("changes")
        }
        client.duringInvalidate = { order.append("invalidate") }
        c.handle(.terminated)
        c.handle(note()); c.islandOpened(); c.perform(.next)
        #expect(order == ["changes", "invalidate"])
        #expect(taps.lives == [true, false] && client.refreshes == 2)
        #expect(client.invalidations == 1 && client.sent.isEmpty)
    }

    @Test func appliedGeometryFlagIsOwnedByPanel() {
        let (c, _, state, taps) = make()
        c.handle(.launched); c.handle(note())
        #expect(!state.live && taps.lives == [true])
        state.live = true
        c.handle(note(.paused)); c.handle(.terminated)
        #expect(state.live && taps.lives == [true, false])
    }

    @Test func fakeSynchronousRefreshWorksWithOwnerWiring() {
        let fake = FakeSpotifyClient(state: .playing, now: { self.t0 })
        let state = AppState(), c = SpotifyCoordinator(client: fake, state: AppState())
        let wired = SpotifyCoordinator(client: fake, state: state)
        fake.onEvent = { wired.handle($0) }
        wired.handle(.launched); fake.setState(.playing)
        #expect(fake.refreshCount == 1 && state.nowPlaying?.title == "Fake Track One")
        #expect(c.model.availability == .notRunning)
        wired.perform(.next)
        #expect(fake.refreshCount == 2 && state.nowPlaying?.trackID == "fake:2")
    }
}

extension FakeSpotifyClientTests {
    @Test func clockFreezesOnPauseAndResumesFromStoredPosition() {
        let clock = FakeClock(), box = EventBox()
        let fake = FakeSpotifyClient(state: .playing, now: { clock.date })
        fake.onEvent = { box.events.append($0) }
        clock.advance(12); fake.refresh()
        #expect(reading(box.events.last)?.0.position == 12)
        fake.send(.playPause)
        clock.advance(100); fake.refresh()
        #expect(reading(box.events.last)?.0.position == 12)
        fake.send(.playPause)
        clock.advance(8); fake.refresh()
        #expect(reading(box.events.last)?.0.position == 20)
        if case .reading(_, _, let at)? = box.events.last { #expect(at == clock.date) }
        else { Issue.record("Expected reading") }
    }

    @Test func controlsWrapAndResetPositionWithoutChangingPauseState() {
        let clock = FakeClock(), box = EventBox()
        let fake = FakeSpotifyClient(state: .paused, now: { clock.date })
        fake.onEvent = { box.events.append($0) }
        fake.send(.previous)
        #expect(reading(box.events.last)?.0.trackID == "fake:3")
        #expect(reading(box.events.last)?.0.duration == 240)
        fake.send(.next)
        #expect(reading(box.events.last)?.0.trackID == "fake:1")
        fake.setState(.playing); clock.advance(30); fake.send(.next)
        #expect(reading(box.events.last)?.0.position == 0)
        fake.setState(.paused); clock.advance(30); fake.refresh()
        #expect(reading(box.events.last)?.0.position == 0)
        #expect(reading(box.events.last)?.0.artist == "shima fake")
        #expect(reading(box.events.last)?.0.album == "Fixture")
    }

    @Test func clockClampsAtDurationAndInvalidateIsNoOp() {
        let clock = FakeClock(), box = EventBox()
        let fake = FakeSpotifyClient(state: .playing, now: { clock.date })
        fake.onEvent = { box.events.append($0) }
        clock.advance(500); fake.refresh()
        #expect(reading(box.events.last)?.0.position == 200)
        fake.invalidate(); fake.send(.next); fake.refresh()
        #expect(reading(box.events.last)?.0.trackID == "fake:2")
        #expect(reading(box.events.last)?.0.artworkURL == nil)
        #expect(fake.refreshCount == 2)
    }

    @Test func stoppedAndPausedInitialStatesDoNotAdvanceUntilPlaying() {
        for playback in [PlaybackState.paused, .stopped] {
            let clock = FakeClock(), box = EventBox()
            let fake = FakeSpotifyClient(state: playback, now: { clock.date })
            fake.onEvent = { box.events.append($0) }
            clock.advance(40); fake.refresh()
            #expect(reading(box.events.last)?.0.state == playback)
            #expect(reading(box.events.last)?.0.position == 0)
            fake.setState(.playing); clock.advance(3); fake.refresh()
            #expect(reading(box.events.last)?.0.position == 3)
        }
    }
}
