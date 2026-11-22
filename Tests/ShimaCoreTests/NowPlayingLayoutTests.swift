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
        #expect(p == CGRect(x: 203, y: 157, width: 28, height: 28))
        #expect(m == CGRect(x: 245, y: 155, width: 32, height: 32))
        #expect(n == CGRect(x: 291, y: 157, width: 28, height: 28))
        #expect((p.minX + n.maxX) / 2 == NowPlayingLayout.column.midX && m.midX == NowPlayingLayout.column.midX)
        #expect(m.minX - p.maxX == 14 && n.minX - m.maxX == 14 && p.midY == m.midY && n.midY == m.midY)
        #expect(NowPlayingLayout.column.contains(p) && NowPlayingLayout.column.contains(m) && NowPlayingLayout.column.contains(n))
    }
    @Test func controlCentersOnThisMac() {
        #expect(NowPlayingLayout.controlCenter(.previous, notchMidX: 735.5, topY: 0) == CGPoint(x: 752.5, y: 171))
        #expect(NowPlayingLayout.controlCenter(.playPause, notchMidX: 735.5, topY: 0) == CGPoint(x: 796.5, y: 171))
        #expect(NowPlayingLayout.controlCenter(.next, notchMidX: 735.5, topY: 0) == CGPoint(x: 840.5, y: 171))
    }
    @Test func controlCentersOnOffsetScreen() {
        #expect(NowPlayingLayout.controlCenter(.playPause, notchMidX: -735.5, topY: -900) == CGPoint(x: -674.5, y: -729))
    }
    @Test func wingContentFits() {
        let bars = CGFloat(NowPlayingLayout.barCount) * NowPlayingLayout.barWidth + CGFloat(NowPlayingLayout.barCount - 1) * NowPlayingLayout.barGap
        #expect(bars == NowPlayingLayout.equalizer.width && bars <= IslandLayout.liveWingWidth)
        #expect(NowPlayingLayout.miniArtwork.width <= IslandLayout.liveWingWidth && NowPlayingLayout.miniArtwork.height <= 32)
    }
    @Test func homeButtonIsTheFirstHeaderIconLeftOfTheNotch() {
        let g = NowPlayingLayout.settingsButton
        #expect(g == CGRect(x: 14, y: 5, width: 24, height: 22))
        #expect(island.contains(g) && g.maxY <= 32 && g.maxX < (island.width - 179) / 2)
    }
    @Test func tabIconsFollowHomeInsideTheStripWithoutOverlap() {
        let home = NowPlayingLayout.settingsButton
        let music = NowPlayingLayout.tabRect(.music)
        let camera = NowPlayingLayout.tabRect(.camera)
        #expect(music == NowPlayingLayout.tabIcon)
        #expect(music.minX > home.maxX && camera.minX > music.maxX)
        #expect(camera.maxY <= 32 && camera.maxX < (island.width - 179) / 2)
        for r in [home, music, camera] { #expect(!r.intersects(NowPlayingLayout.artwork)) }
    }
    @Test func cameraPanelIsPreviewLeftAndControlColumnRight() {
        let preview = NowPlayingLayout.cameraPreview
        let column = [NowPlayingLayout.cameraLive, NowPlayingLayout.cameraMirror, NowPlayingLayout.cameraSwitch,
                      NowPlayingLayout.cameraClose, NowPlayingLayout.cameraNote]
        #expect(island.contains(preview) && preview.minY >= 33)
        for (i, r) in column.enumerated() {
            #expect(island.contains(r) && r.minX > preview.maxX && r.width == 104)
            if i > 0 { #expect(r.minY >= column[i - 1].maxY) }
        }
        #expect(column.last!.maxY <= preview.maxY)
    }
    @Test func homeButtonClearsTheNowPlayingContent() {
        let g = NowPlayingLayout.settingsButton
        for r in [NowPlayingLayout.titleRect, NowPlayingLayout.artwork] + SpotifyCommand.allCases.map(NowPlayingLayout.controlRect) {
            #expect(!g.intersects(r))
        }
    }
    @Test func homeButtonCenterOnThisMac() {
        #expect(NowPlayingLayout.settingsButtonCenter(notchMidX: 735.5, topY: 0) == CGPoint(x: 561.5, y: 16))
    }
    @Test func homeButtonCenterOnOffsetScreen() {
        #expect(NowPlayingLayout.settingsButtonCenter(notchMidX: -735.5, topY: -900) == CGPoint(x: -909.5, y: -884))
    }
}
