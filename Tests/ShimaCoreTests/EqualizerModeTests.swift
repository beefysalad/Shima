import Testing
@testable import ShimaCore

@Suite struct EqualizerModeTests {
    typealias P = EqualizerPolicy

    @Test func storedValuesRoundTrip() {
        for mode in EqualizerMode.allCases { #expect(EqualizerMode(stored: mode.rawValue) == mode) }
        #expect(EqualizerMode.allCases.map(\.rawValue) == ["animated", "whenOpen", "off"])
    }
    @Test func unknownOrMissingFallsBackToAnimated() {
        #expect(EqualizerMode(stored: nil) == .animated)
        #expect(EqualizerMode(stored: "") == .animated)
        #expect(EqualizerMode(stored: "Off") == .animated)
        #expect(EqualizerMode.default == .animated)
    }
    @Test func titles() {
        #expect(EqualizerMode.allCases.map(\.title) == ["Animated", "Only when open", "Off"])
    }
    @Test func visibleCollapsedOnlyWhenLive() {
        #expect(P.isVisible(island: .collapsed, live: true, content: .track))
        #expect(!P.isVisible(island: .collapsed, live: false, content: .track))
    }
    @Test func peekKeepsWingsLikeCollapsed() {
        #expect(P.isVisible(island: .peek, live: true, content: .track))
        #expect(!P.isVisible(island: .peek, live: false, content: .track))
        #expect(P.isAnimating(.animated, island: .peek, live: true, content: .track, playing: true, frozen: false))
        #expect(!P.isAnimating(.whenOpen, island: .peek, live: true, content: .track, playing: true, frozen: false))
    }
    @Test func visibleExpandedOnlyWithTrack() {
        #expect(P.isVisible(island: .expanded, live: false, content: .track))
        for content in [NowPlayingContent.notRunning, .permissionDenied, .nothingPlaying] {
            #expect(!P.isVisible(island: .expanded, live: true, content: content))
        }
    }
    @Test func animatedMatchesM1WhenCollapsed() {
        #expect(P.isAnimating(.animated, island: .collapsed, live: true, content: .track, playing: true, frozen: false))
        #expect(!P.isAnimating(.animated, island: .collapsed, live: false, content: .track, playing: true, frozen: false))
    }
    @Test func animatedAlsoAnimatesInTheOpenIsland() {
        #expect(P.isAnimating(.animated, island: .expanded, live: true, content: .track, playing: true, frozen: false))
    }
    @Test func whenOpenAnimatesOnlyExpanded() {
        #expect(!P.isAnimating(.whenOpen, island: .collapsed, live: true, content: .track, playing: true, frozen: false))
        #expect(P.isAnimating(.whenOpen, island: .expanded, live: true, content: .track, playing: true, frozen: false))
        #expect(!P.isAnimating(.whenOpen, island: .expanded, live: true, content: .permissionDenied, playing: true, frozen: false))
    }
    @Test func offNeverAnimates() {
        for island in [IslandMode.collapsed, .expanded] {
            for live in [false, true] {
                #expect(!P.isAnimating(.off, island: island, live: live, content: .track, playing: true, frozen: false))
            }
        }
    }
    @Test func pausedOrFrozenNeverAnimates() {
        for mode in EqualizerMode.allCases {
            for island in [IslandMode.collapsed, .expanded] {
                #expect(!P.isAnimating(mode, island: island, live: true, content: .track, playing: false, frozen: false))
                #expect(!P.isAnimating(mode, island: island, live: true, content: .track, playing: true, frozen: true))
            }
        }
    }
    @Test @MainActor func appStateDefaultsToAnimated() {
        #expect(AppState().equalizerMode == .animated)
    }

    @Test func policyMatrix() {
        // Visibility depends on live while collapsed and track content while expanded.
        let visibilityCases: [(IslandMode, Bool, NowPlayingContent, Bool)] = [
            (.collapsed, false, .track, false),
            (.collapsed, false, .notRunning, false),
            (.collapsed, false, .permissionDenied, false),
            (.collapsed, false, .nothingPlaying, false),
            (.collapsed, true, .track, true),
            (.collapsed, true, .notRunning, true),
            (.collapsed, true, .permissionDenied, true),
            (.collapsed, true, .nothingPlaying, true),
            (.expanded, false, .track, true),
            (.expanded, false, .notRunning, false),
            (.expanded, false, .permissionDenied, false),
            (.expanded, false, .nothingPlaying, false),
            (.expanded, true, .track, true),
            (.expanded, true, .notRunning, false),
            (.expanded, true, .permissionDenied, false),
            (.expanded, true, .nothingPlaying, false),
        ]
        for (island, live, content, visible) in visibilityCases {
            #expect(P.isVisible(island: island, live: live, content: content) == visible)
            for mode in EqualizerMode.allCases {
                for playing in [false, true] {
                    for frozen in [false, true] {
                        let modeAllowsAnimation = mode == .animated || (mode == .whenOpen && island == .expanded)
                        let expected = visible && modeAllowsAnimation && playing && !frozen
                        #expect(P.isAnimating(mode, island: island, live: live, content: content,
                                              playing: playing, frozen: frozen) == expected)
                    }
                }
            }
        }
    }
}
