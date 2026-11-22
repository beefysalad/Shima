import CoreGraphics
import Testing
@testable import ShimaCore

@Suite struct NowPlayingLayoutTests {
    let island = CGRect(x: 0, y: 0, width: 360, height: 165)
    var rects: [CGRect] { [NowPlayingLayout.artwork, NowPlayingLayout.column] + SpotifyCommand.allCases.map(NowPlayingLayout.controlRect) }

    @Test func artworkAndColumnMatchSpec() {
        #expect(NowPlayingLayout.artwork == CGRect(x: 14, y: 44, width: 88, height: 88))
        #expect(NowPlayingLayout.column.minX == 116 && NowPlayingLayout.column.maxX == 346)
    }
    @Test func contentSitsBelowTheNotchStripInsideTheIsland() {
        for r in rects { #expect(r.minY >= 32 && island.contains(r)) }
    }
    @Test func controlsAreSizedAndSpaced() {
        let p = NowPlayingLayout.controlRect(.previous), m = NowPlayingLayout.controlRect(.playPause), n = NowPlayingLayout.controlRect(.next)
        #expect(p.size == CGSize(width: 28, height: 28) && n.size == p.size && m.size == CGSize(width: 32, height: 32))
        #expect(p == CGRect(x: 173, y: 114, width: 28, height: 28))
        #expect(m == CGRect(x: 215, y: 112, width: 32, height: 32))
        #expect(n == CGRect(x: 261, y: 114, width: 28, height: 28))
        #expect(m.minX - p.maxX == 14 && n.minX - m.maxX == 14 && p.midY == m.midY && n.midY == m.midY)
        #expect(NowPlayingLayout.column.contains(p) && NowPlayingLayout.column.contains(m) && NowPlayingLayout.column.contains(n))
    }
    @Test func controlCentersOnThisMac() {
        #expect(NowPlayingLayout.controlCenter(.previous, notchMidX: 735.5, topY: 0) == CGPoint(x: 742.5, y: 128))
        #expect(NowPlayingLayout.controlCenter(.playPause, notchMidX: 735.5, topY: 0) == CGPoint(x: 786.5, y: 128))
        #expect(NowPlayingLayout.controlCenter(.next, notchMidX: 735.5, topY: 0) == CGPoint(x: 830.5, y: 128))
    }
    @Test func controlCentersOnOffsetScreen() {
        #expect(NowPlayingLayout.controlCenter(.playPause, notchMidX: -735.5, topY: -900) == CGPoint(x: -684.5, y: -772))
    }
    @Test func wingContentFits() {
        let bars = CGFloat(NowPlayingLayout.barCount) * NowPlayingLayout.barWidth + CGFloat(NowPlayingLayout.barCount - 1) * NowPlayingLayout.barGap
        #expect(bars == NowPlayingLayout.equalizer.width && bars <= IslandLayout.liveWingWidth)
        #expect(NowPlayingLayout.miniArtwork.width <= IslandLayout.liveWingWidth && NowPlayingLayout.miniArtwork.height <= 32)
    }
}
