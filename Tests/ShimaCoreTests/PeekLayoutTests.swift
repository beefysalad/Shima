import CoreGraphics
import Testing
@testable import ShimaCore

@Suite struct PeekLayoutTests {
    let island = CGRect(x: 0, y: 0, width: IslandLayout.peek.width, height: IslandLayout.peek.height)
    var rects: [CGRect] {
        [PeekLayout.badge, PeekLayout.title, PeekLayout.subtitle, PeekLayout.subtitleWide, PeekLayout.batteryGroup]
    }

    @Test func everythingIsInsideThePeekIslandBelowTheNotchStrip() {
        #expect(island.size == CGSize(width: 340, height: 76))
        for r in rects { #expect(island.contains(r) && r.minY >= 32) }
    }

    @Test func badgeIsThirtyByThirtyAndTextSitsRightOfIt() {
        #expect(PeekLayout.badge.size == CGSize(width: 30, height: 30))
        for r in [PeekLayout.title, PeekLayout.subtitle, PeekLayout.subtitleWide] { #expect(r.minX >= PeekLayout.badge.maxX) }
    }

    @Test func batteryGroupNeverOverlapsTheNarrowSubtitleOrTitle() {
        #expect(!PeekLayout.batteryGroup.intersects(PeekLayout.subtitle))
        #expect(!PeekLayout.batteryGroup.intersects(PeekLayout.title))
        #expect(PeekLayout.batteryGroup.maxX == 318)
    }

    @Test func batteryContentFitsTheGroup() {
        // "100%" at 11.5 pt semibold is about 30 pt wide.
        #expect(30 + PeekLayout.batteryGap + PeekLayout.batteryGlyph.width <= PeekLayout.batteryGroup.width)
        #expect(PeekLayout.batteryGroup.midY == 55)
    }

    @Test func titleAndSubtitleStackWithoutOverlap() {
        #expect(PeekLayout.title.maxY <= PeekLayout.subtitle.minY)
        #expect(PeekLayout.subtitleWide.minX == PeekLayout.subtitle.minX)
    }
}
