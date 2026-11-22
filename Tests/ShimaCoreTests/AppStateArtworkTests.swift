import Foundation
import Testing
@testable import ShimaCore

@Suite @MainActor struct AppStateArtworkTests {
    private func track(_ id: String = "a") -> NowPlaying {
        NowPlaying(trackID: id, title: "Title", artist: "Artist", album: "Album",
                   artworkURL: URL(string: "https://example.com/\(id)"), duration: 100,
                   position: 0, positionDate: Date(timeIntervalSince1970: 0), state: .playing)
    }

    @Test func bindingSynchronouslySuppliesInitialNil() {
        let state = AppState()
        var calls = 0
        state.onArtworkChange = { id, url in
            #expect(id == nil && url == nil)
            calls += 1
        }
        #expect(calls == 1)
    }

    @Test func bindingSynchronouslySuppliesExistingIdentity() {
        let state = AppState()
        state.nowPlaying = track()
        var ids: [String?] = []
        state.onArtworkChange = { id, _ in ids.append(id) }
        #expect(ids == ["a"])
    }

    @Test func rapidChangesAndTerminationAreDeliveredSynchronously() {
        let state = AppState()
        var ids: [String?] = []
        state.onArtworkChange = { id, _ in ids.append(id) }
        state.nowPlaying = track("a")
        state.nowPlaying = track("b")
        state.nowPlaying = track("a")
        state.nowPlaying = nil
        #expect(ids == [nil, "a", "b", "a", nil])
        state.nowPlaying = track("a")
        #expect(ids == [nil, "a", "b", "a", nil, "a"])
    }

    @Test func onlyIdentityChangesInvokeCallback() {
        let state = AppState()
        state.nowPlaying = track()
        var calls = 0
        state.onArtworkChange = { _, _ in calls += 1 }
        state.nowPlaying?.position = 25
        state.nowPlaying?.state = .paused
        state.nowPlaying?.title = "Updated title"
        #expect(calls == 1)
        state.nowPlaying?.artworkURL = URL(string: "https://example.com/new")
        #expect(calls == 2)
    }
}
