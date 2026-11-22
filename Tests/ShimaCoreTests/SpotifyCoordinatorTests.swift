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

@MainActor final class Taps {
    var lives: [Bool] = []
    var changes: [[SpotifyChange]] = []
}

@Suite @MainActor struct SpotifyCoordinatorTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    let art = URL(string: "https://i.scdn.co/image/a")!

    func make(scheduler: ManualScheduler = ManualScheduler()) -> (SpotifyCoordinator, TestClient, AppState, Taps) {
        let client = TestClient(), state = AppState(), taps = Taps()
        let c = SpotifyCoordinator(client: client, state: state, scheduler: scheduler)
        c.onLiveChange = { taps.lives.append($0) }
        c.onChanges = { taps.changes.append($0) }
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
    @Test func launchBroadcastOrderStoppedThenFullPausedStaysIdle() {
        let (c, client, state, taps) = make()
        c.handle(.launched)
        c.handle(.reading(SpotifyReading(state: .stopped), source: .notification, at: t0))
        c.handle(note(.paused))
        #expect(state.content == .track && state.nowPlaying?.trackID == "a")
        #expect(taps.lives == [] && client.sent.isEmpty && client.refreshes == 2)  // sparse Stopped, then missing artwork; never on launch itself
    }
    @Test func relaunchAfterQuitIsLiveAgain() {
        let (c, _, state, taps) = make()
        c.handle(.launched); c.handle(note()); c.handle(.terminated)
        c.handle(.launched); c.handle(note(.playing, "b"))
        #expect(taps.lives == [true, false, true] && state.nowPlaying?.trackID == "b")
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
        let coordinator = SpotifyCoordinator(client: client, state: AppState(), scheduler: ManualScheduler())
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
        client.duringRefresh = {
            order.append("refresh")
            c.handle(self.script(art: self.art))
        }
        c.handle(note())
        #expect(order == ["changes", "live", "refresh"])
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
        let state = AppState(), c = SpotifyCoordinator(client: fake, state: AppState(), scheduler: ManualScheduler())
        let wired = SpotifyCoordinator(client: fake, state: state, scheduler: ManualScheduler())
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

extension SpotifyCoordinatorTests {
    func running(_ scheduler: ManualScheduler) -> (SpotifyCoordinator, TestClient, AppState) {
        let (c, client, state, _) = make(scheduler: scheduler)
        c.handle(.launched); c.handle(script(art: art))
        client.refreshes = 0
        return (c, client, state)
    }

    @Test func followUpDelayIsTwoFiftyMilliseconds() {
        #expect(SpotifyCoordinator.commandFollowUpDelay == .milliseconds(250))
    }

    @Test func followUpDoesNotRunBeforeDelay() {
        let s = ManualScheduler(), (c, client, _) = running(s)
        c.handle(.commandSucceeded(.previous))
        s.advance(by: .milliseconds(249))
        #expect(client.refreshes == 0)
    }

    @Test func followUpRefreshesExactlyOnceAtDelay() {
        let s = ManualScheduler(), (c, client, _) = running(s)
        c.handle(.commandSucceeded(.previous))
        s.advance(by: .milliseconds(250))
        s.advance(by: .seconds(10))
        #expect(client.refreshes == 1 && s.pendingCount == 0)
    }

    @Test func rapidCommandsLeaveOneFollowUp() {
        let s = ManualScheduler(), (c, client, _) = running(s)
        c.handle(.commandSucceeded(.previous))
        s.advance(by: .milliseconds(100))
        c.handle(.commandSucceeded(.previous))
        #expect(s.pendingCount == 1)
        s.advance(by: .milliseconds(249))
        #expect(client.refreshes == 0)
        s.advance(by: .milliseconds(1))
        s.advance(by: .seconds(10))
        #expect(client.refreshes == 1)
    }

    @Test func terminateCancelsPendingFollowUp() {
        let s = ManualScheduler(), (c, client, _) = running(s)
        c.handle(.commandSucceeded(.previous))
        c.handle(.terminated)
        #expect(s.pendingCount == 0)
        s.advance(by: .seconds(1))
        #expect(client.refreshes == 0)
    }

    @Test func stopCancelsPendingFollowUp() {
        let s = ManualScheduler(), (c, client, _) = running(s)
        c.handle(.commandSucceeded(.previous))
        c.stop()
        s.advance(by: .seconds(1))
        #expect(s.pendingCount == 0 && client.refreshes == 0)
    }

    @Test func commandSucceededWhileNotRunningSchedulesNothing() {
        let s = ManualScheduler(), (c, client, _, _) = make(scheduler: s)
        c.handle(.commandSucceeded(.previous))
        s.advance(by: .seconds(1))
        #expect(s.pendingCount == 0 && client.refreshes == 0)
    }

    @Test func failedCommandSchedulesNoFollowUp() {
        let s = ManualScheduler(), (c, client, _) = running(s)
        c.perform(.previous)  // the client reports failure by sending no commandSucceeded
        s.advance(by: .seconds(1))
        #expect(client.sent == [.previous] && client.refreshes == 0 && s.pendingCount == 0)
    }

    @Test func idleSchedulesNothing() {
        let s = ManualScheduler(), (_, client, _) = running(s)
        s.advance(by: .seconds(60))
        #expect(s.pendingCount == 0 && client.refreshes == 0)
    }

    @Test func restartedPositionUpdatesAnchorAfterFollowUp() {
        let s = ManualScheduler(), (c, client, state) = running(s)
        let later = t0.addingTimeInterval(7)
        c.handle(.reading(SpotifyReading(state: .playing, trackID: "a", title: "T", artist: "A", position: 6),
                          source: .notification, at: t0.addingTimeInterval(1)))
        // Spotify restarts the same track silently; only the follow-up read sees position 0.
        client.duringRefresh = {
            c.handle(.reading(SpotifyReading(state: .playing, trackID: "a", title: "T", artist: "A", duration: 200,
                                             position: 0.25, artworkURL: self.art), source: .script, at: later))
        }
        c.handle(.commandSucceeded(.previous))
        #expect(state.nowPlaying?.position == 6)
        s.advance(by: .milliseconds(250))
        #expect(state.nowPlaying?.position == 0.25 && state.nowPlaying?.positionDate == later)
    }

    @Test func nextAndPlayPauseScheduleNoFollowUp() {
        let s = ManualScheduler(), (c, client, _) = running(s)
        c.handle(.commandSucceeded(.next))
        c.handle(.commandSucceeded(.playPause))
        s.advance(by: .seconds(10))
        #expect(s.pendingCount == 0 && client.refreshes == 0)
    }

    private func followUpReading(_ s: PlaybackState, _ id: String, _ position: Double?, at: Date) -> SpotifyEvent {
        .reading(SpotifyReading(state: s, trackID: id, title: "X", artist: "Y", album: "Z", duration: 99,
                                position: position, artworkURL: nil), source: .script, at: at)
    }

    @Test func staleFollowUpReadingKeepsPausedState() {
        let s = ManualScheduler(), (c, client, state) = running(s)
        c.handle(note(.paused))
        let later = t0.addingTimeInterval(5)
        client.duringRefresh = { c.handle(self.followUpReading(.playing, "a", 3, at: later)) }
        c.handle(.commandSucceeded(.previous))
        s.advance(by: .milliseconds(250))
        #expect(state.nowPlaying?.state == .paused && c.model.nowPlaying?.state == .paused)
        #expect(state.nowPlaying?.title == "T" && state.nowPlaying?.position == 3)
    }

    @Test func followUpReadingForDifferentTrackIsIgnored() {
        let s = ManualScheduler(), (c, client, state) = running(s)
        let before = state.nowPlaying
        client.duringRefresh = { c.handle(self.followUpReading(.playing, "b", 0, at: self.t0.addingTimeInterval(5))) }
        c.handle(.commandSucceeded(.previous))
        s.advance(by: .milliseconds(250))
        #expect(state.nowPlaying == before && state.nowPlaying?.trackID == "a")
    }

    @Test func laterScriptReadingsApplyNormallyAfterFollowUp() {
        let s = ManualScheduler(), (c, client, state) = running(s)
        client.duringRefresh = { c.handle(self.followUpReading(.playing, "a", 0.5, at: self.t0)) }
        c.handle(.commandSucceeded(.previous))
        s.advance(by: .milliseconds(250))
        c.handle(followUpReading(.paused, "a", 2, at: t0.addingTimeInterval(1)))
        #expect(state.nowPlaying?.state == .paused)
    }

    @Test func failedFollowUpClearsPendingFlag() {
        let s = ManualScheduler(), (c, client, state) = running(s)
        client.duringRefresh = { c.handle(.refreshFailed) }
        c.handle(.commandSucceeded(.previous))
        s.advance(by: .milliseconds(250))
        c.handle(script("a", art: art))
        #expect(state.nowPlaying?.artworkURL == art)
    }

    @Test func permissionDeniedClearsPendingFlagAndLaterReadingRecovers() {
        let s = ManualScheduler(), (c, client, state) = running(s)
        client.duringRefresh = { c.handle(.permissionDenied) }
        c.handle(.commandSucceeded(.previous))
        s.advance(by: .milliseconds(250))
        #expect(state.spotifyAvailability == .permissionDenied)
        c.handle(script("a", art: art))
        #expect(state.spotifyAvailability == .running && state.nowPlaying?.artworkURL == art)
    }

    @Test func artworkReadingIsAppliedFullyAfterFailedFollowUp() {
        let s = ManualScheduler(), (c, client, state) = running(s)
        c.handle(script("b", art: nil))
        client.duringRefresh = { c.handle(.refreshFailed) }
        c.handle(.commandSucceeded(.previous))
        s.advance(by: .milliseconds(250))
        let other = URL(string: "https://i.scdn.co/image/b")!
        c.handle(script("b", art: other))
        #expect(state.nowPlaying?.artworkURL == other)
    }

    @Test func refreshFailedWithoutPendingFollowUpIsHarmless() {
        let (c, _, state, taps) = make()
        c.handle(.launched); c.handle(note())
        let before = state.nowPlaying, changes = taps.changes.count
        c.handle(.refreshFailed)
        #expect(state.nowPlaying == before && taps.changes.count == changes)
    }

    @Test func applyPositionOnlyInPermissionDeniedModelUsesNormalReducer() {
        var m = SpotifyModel()
        _ = m.apply(.launched); _ = m.apply(.permissionDenied)
        let reading = SpotifyReading(state: .playing, trackID: "a", title: "T", artist: "A", position: 3)
        let (np, changes) = m.applyPositionOnly(reading, at: t0)
        #expect(m.availability == .running && np?.trackID == "a")
        #expect(changes.contains(.availabilityChanged(.running)))
    }
}
