import CoreGraphics
import Testing
@testable import ShimaCore

@Suite struct ScreenPickTests {
    let frames = [CGRect(x: 0, y: 0, width: 1470, height: 956), CGRect(x: 1470, y: -200, width: 2560, height: 1440)]

    @Test func pointerScreenWins() {
        #expect(ScreenPick.choose(pointer: CGPoint(x: 2000, y: 300), frames: frames, island: 0, main: 0) == 1)
        #expect(ScreenPick.choose(pointer: CGPoint(x: 100, y: 100), frames: frames, island: 1, main: 1) == 0)
    }
    @Test func fallsBackToIslandThenMain() {
        let off = CGPoint(x: -5000, y: 0)
        #expect(ScreenPick.choose(pointer: off, frames: frames, island: 1, main: 0) == 1)
        #expect(ScreenPick.choose(pointer: off, frames: frames, island: nil, main: 0) == 0)
        #expect(ScreenPick.choose(pointer: off, frames: frames, island: nil, main: nil) == nil)
    }
    @Test func topEdgeCountsAsInside() {
        #expect(ScreenPick.index(containing: CGPoint(x: 700, y: 956), in: frames) == 0)
    }
}
