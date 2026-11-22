import Testing
@testable import ShimaCore

@Suite @MainActor
struct AppStateTabObserverTests {
    @Test func bothObserversReceiveEveryChangeSynchronously() {
        let state = AppState()
        var first: [IslandTab] = []
        var second: [IslandTab] = []
        state.addTabContextObserver { _, tab in first.append(tab) }
        state.addTabContextObserver { _, tab in second.append(tab) }

        state.mode = .expanded
        #expect(first == [.music, .music])
        #expect(second == first)
        state.selectedTab = .calendar
        #expect(first == [.music, .music, .calendar])
        #expect(second == first)
    }

    @Test func lateObserverReceivesCurrentContextOnce() {
        let state = AppState()
        state.mode = .expanded
        state.selectedTab = .calendar
        var calls = 0
        state.addTabContextObserver { mode, tab in
            calls += 1
            #expect(mode == .expanded)
            #expect(tab == .calendar)
        }
        #expect(calls == 1)
    }

    @Test func collapseDeliversOnlyCollapsedMusic() {
        let state = AppState()
        state.mode = .expanded
        state.selectedTab = .calendar
        var calls = 0
        state.addTabContextObserver { mode, tab in
            calls += 1
            if calls > 1 {
                #expect(mode == .collapsed)
                #expect(tab == .music)
            }
        }

        state.mode = .collapsed
        #expect(state.selectedTab == .music)
        #expect(calls == 2)
    }
}
