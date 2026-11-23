import CoreGraphics
import Testing
@testable import ShimaCore

@Suite struct NowPlayingLayoutTests {
    let island = CGRect(x: 0, y: 0, width: IslandLayout.expanded.width, height: IslandLayout.expanded.height)
    var rects: [CGRect] { [NowPlayingLayout.artwork, NowPlayingLayout.column] + SpotifyCommand.allCases.map(NowPlayingLayout.controlRect) }

    @Test func artworkAndColumnMatchSpec() {
        #expect(NowPlayingLayout.artwork == CGRect(x: 18, y: 50, width: 104, height: 104))
        #expect(NowPlayingLayout.column.minX == 140 && NowPlayingLayout.column.maxX == 422)
    }
    @Test func contentSitsBelowTheNotchStripInsideTheIsland() {
        for r in rects { #expect(r.minY >= 32 && island.contains(r)) }
    }
    @Test func controlsAreSizedAndSpaced() {
        let p = NowPlayingLayout.controlRect(.previous), m = NowPlayingLayout.controlRect(.playPause), n = NowPlayingLayout.controlRect(.next)
        #expect(p.size == CGSize(width: 28, height: 28) && n.size == p.size && m.size == CGSize(width: 32, height: 32))
        #expect(p == CGRect(x: 223, y: 157, width: 28, height: 28))
        #expect(m == CGRect(x: 265, y: 155, width: 32, height: 32))
        #expect(n == CGRect(x: 311, y: 157, width: 28, height: 28))
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
    @Test func homeIsFirstTab() {
        #expect(IslandTab.allCases == [.home, .music, .camera, .calendar])
        #expect(NowPlayingLayout.tabRect(.home) == CGRect(x: 12, y: 5, width: 22, height: 22))
    }
    @MainActor @Test func defaultTabIsMusicAndCollapseSnapsToMusic() {
        let state = AppState()
        #expect(state.selectedTab == .music)
        state.mode = .expanded
        state.selectedTab = .home
        state.mode = .collapsed
        #expect(state.selectedTab == .music)
    }
    @Test func tabIconsAreOnA24PitchInsideTheStripWithoutOverlap() {
        let icons = IslandTab.allCases.map(NowPlayingLayout.tabRect)
        #expect(icons.map(\.minX) == [12, 36, 60, 84])
        #expect(icons.allSatisfy { $0.width == 22 && $0.height == 22 && $0.minY == 5 })
        for (a, b) in zip(icons, icons.dropFirst()) { #expect(a.maxX <= b.minX) }
        for r in icons { #expect(!r.intersects(NowPlayingLayout.artwork)) }
    }
    @Test func tabRectsEndBeforeNotch() {
        #expect(NowPlayingLayout.tabRect(.calendar).maxX <= 106)
        #expect(NowPlayingLayout.tabRect(.calendar).maxX < (island.width - 179) / 2)
    }
    @Test func settingsButtonInRightWing() {
        let g = NowPlayingLayout.settingsButton
        #expect(g == CGRect(x: 406, y: 5, width: 22, height: 22))
        #expect(island.contains(g) && g.maxY <= 32)
        #expect(g.minX > (island.width + 179) / 2)
    }
    @Test func settingsButtonClearsTheNowPlayingContent() {
        let g = NowPlayingLayout.settingsButton
        for r in [NowPlayingLayout.titleRect, NowPlayingLayout.artwork] + SpotifyCommand.allCases.map(NowPlayingLayout.controlRect) {
            #expect(!g.intersects(r))
        }
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
    @Test func settingsButtonCenterOnThisMac() {
        #expect(NowPlayingLayout.settingsButtonCenter(notchMidX: 735.5, topY: 0) == CGPoint(x: 932.5, y: 16))
    }
    @Test func settingsButtonCenterOnOffsetScreen() {
        #expect(NowPlayingLayout.settingsButtonCenter(notchMidX: -735.5, topY: -900) == CGPoint(x: -538.5, y: -884))
    }

    // 440 pt island: the notch (179 pt) stays centred, so its zone is x 130.5..309.5.
    var notchZone: CGRect { CGRect(x: (island.width - 179) / 2, y: 0, width: 179, height: 32) }

    @Test func islandIs440WideAndNotchZoneMoves() {
        #expect(IslandLayout.expanded.width == 440 && island.width == 440)
        #expect(notchZone == CGRect(x: 130.5, y: 0, width: 179, height: 32))
    }
    @Test func gearIsInsetTwelveFromTheRightEdgeAndClearsTheNotch() {
        let g = NowPlayingLayout.settingsButton
        #expect(g.maxX == 428 && g.maxX == island.width - 12)
        #expect(!g.intersects(notchZone) && g.minX > notchZone.maxX)
    }
    @Test func cameraRectsMatchTheWideMockup() {
        #expect(NowPlayingLayout.cameraPreview == CGRect(x: 14, y: 40, width: 298, height: 146))
        #expect(NowPlayingLayout.cameraLive == CGRect(x: 322, y: 40, width: 104, height: 16))
        #expect(NowPlayingLayout.cameraMirror == CGRect(x: 322, y: 61, width: 104, height: 30))
        #expect(NowPlayingLayout.cameraSwitch == CGRect(x: 322, y: 96, width: 104, height: 30))
        #expect(NowPlayingLayout.cameraClose == CGRect(x: 322, y: 131, width: 104, height: 30))
        #expect(NowPlayingLayout.cameraNote == CGRect(x: 322, y: 165, width: 104, height: 21))
    }
    @Test func musicColumnIs282WideAndControlsAreCentredInIt() {
        #expect(NowPlayingLayout.column == CGRect(x: 140, y: 48, width: 282, height: 140))
        #expect(NowPlayingLayout.column.midX == 281 && NowPlayingLayout.titleWidth == 282)
    }
    @Test func everyContentRectIsInsideTheIslandAndClearOfTheHeaderStripAndNotch() {
        let camera = [NowPlayingLayout.cameraPreview, NowPlayingLayout.cameraLive, NowPlayingLayout.cameraMirror,
                      NowPlayingLayout.cameraSwitch, NowPlayingLayout.cameraClose, NowPlayingLayout.cameraNote]
        let shelf = [ShelfLayout.veil, ShelfLayout.veilTileRow, ShelfLayout.veilTile, ShelfLayout.veilIcon, ShelfLayout.veilCaption,
                     ShelfLayout.veilCount, ShelfLayout.chipRow, ShelfLayout.emptyState, ShelfLayout.statusLine,
                     ShelfLayout.countLabel, ShelfLayout.clearButton]
        let calendar = [CalendarLayout.dateLine, CalendarLayout.dayNumber, CalendarLayout.moreLine, CalendarLayout.emptyLine,
                        CalendarLayout.monthTitle, CalendarLayout.previousMonth, CalendarLayout.nextMonth, CalendarLayout.weekdayRow]
            + CalendarLayout.deniedBoxes + (0..<CalendarLayout.maxRows).map(CalendarLayout.row)
            + (0..<CalendarLayout.maxWeeks).flatMap { w in (0..<7).map { CalendarLayout.cell(week: w, day: $0) } }
        let all = rects + [NowPlayingLayout.titleRect] + camera + shelf + calendar
        for r in all {
            #expect(island.contains(r))
            #expect(!r.intersects(notchZone))
        }
        let header = CGRect(x: 0, y: 0, width: island.width, height: 32)
        for r in all { #expect(r.minY >= header.maxY) }
    }
}
