import CoreGraphics
import Testing
@testable import ShimaCore

@Suite struct NowPlayingLayoutTests {
    let island = CGRect(x: 0, y: 0, width: 400, height: 200)
    var rects: [CGRect] { [NowPlayingLayout.artwork, NowPlayingLayout.column] + SpotifyCommand.allCases.map(NowPlayingLayout.controlRect) }

    @Test func artworkAndColumnMatchSpec() {
        #expect(NowPlayingLayout.artwork == CGRect(x: 18, y: 50, width: 104, height: 104))
        #expect(NowPlayingLayout.column.minX == 140 && NowPlayingLayout.column.maxX == 382)
    }
    @Test func contentSitsBelowTheNotchStripInsideTheIsland() {
        for r in rects { #expect(r.minY >= 32 && island.contains(r)) }
    }
    @Test func controlsAreSizedAndSpaced() {
        let p = NowPlayingLayout.controlRect(.previous), m = NowPlayingLayout.controlRect(.playPause), n = NowPlayingLayout.controlRect(.next)
        #expect(p.size == CGSize(width: 28, height: 28) && n.size == p.size && m.size == CGSize(width: 32, height: 32))
        #expect(p == CGRect(x: 140, y: 157, width: 28, height: 28))
        #expect(m == CGRect(x: 182, y: 155, width: 32, height: 32))
        #expect(n == CGRect(x: 228, y: 157, width: 28, height: 28))
        #expect(m.minX - p.maxX == 14 && n.minX - m.maxX == 14 && p.midY == m.midY && n.midY == m.midY)
        #expect(NowPlayingLayout.column.contains(p) && NowPlayingLayout.column.contains(m) && NowPlayingLayout.column.contains(n))
    }
    @Test func controlCentersOnThisMac() {
        #expect(NowPlayingLayout.controlCenter(.previous, notchMidX: 735.5, topY: 0) == CGPoint(x: 689.5, y: 171))
        #expect(NowPlayingLayout.controlCenter(.playPause, notchMidX: 735.5, topY: 0) == CGPoint(x: 733.5, y: 171))
        #expect(NowPlayingLayout.controlCenter(.next, notchMidX: 735.5, topY: 0) == CGPoint(x: 777.5, y: 171))
    }
    @Test func controlCentersOnOffsetScreen() {
        #expect(NowPlayingLayout.controlCenter(.playPause, notchMidX: -735.5, topY: -900) == CGPoint(x: -737.5, y: -729))
    }
    @Test func wingContentFits() {
        let bars = CGFloat(NowPlayingLayout.barCount) * NowPlayingLayout.barWidth + CGFloat(NowPlayingLayout.barCount - 1) * NowPlayingLayout.barGap
        #expect(bars == NowPlayingLayout.equalizer.width && bars <= IslandLayout.liveWingWidth)
        #expect(NowPlayingLayout.miniArtwork.width <= IslandLayout.liveWingWidth && NowPlayingLayout.miniArtwork.height <= 32)
    }
    @Test func settingsButtonSitsTopRightBelowTheMenuBar() {
        let g = NowPlayingLayout.settingsButton
        #expect(g == CGRect(x: 358, y: 36, width: 24, height: 24))
        #expect(island.contains(g) && g.minY >= 34 && g.maxX == NowPlayingLayout.column.maxX)
    }
    @Test func tabIconSitsInTheHeaderLeftOfTheNotch() {
        let g = NowPlayingLayout.tabIcon
        let notchLeft = (island.width - 179) / 2
        #expect(g == CGRect(x: 14, y: 4, width: 28, height: 24))
        #expect(island.contains(g) && g.maxY <= 32 && g.maxX < notchLeft)
        #expect(!g.intersects(NowPlayingLayout.artwork) && !g.intersects(NowPlayingLayout.settingsButton))
    }
    @Test func settingsButtonClearsTitleArtworkAndControls() {
        let g = NowPlayingLayout.settingsButton
        #expect(NowPlayingLayout.titleRect == CGRect(x: 140, y: 72, width: 242, height: 20))
        for r in [NowPlayingLayout.titleRect, NowPlayingLayout.artwork] + SpotifyCommand.allCases.map(NowPlayingLayout.controlRect) {
            #expect(!g.intersects(r))
        }
        #expect(g.maxY + 12 == NowPlayingLayout.titleTop)
    }
    @Test func settingsButtonCenterOnThisMac() {
        #expect(NowPlayingLayout.settingsButtonCenter(notchMidX: 735.5, topY: 0) == CGPoint(x: 905.5, y: 48))
    }
    @Test func settingsButtonCenterOnOffsetScreen() {
        #expect(NowPlayingLayout.settingsButtonCenter(notchMidX: -735.5, topY: -900) == CGPoint(x: -565.5, y: -852))
    }
}
