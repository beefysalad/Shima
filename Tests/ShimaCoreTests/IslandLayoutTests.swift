import CoreGraphics
import Testing
@testable import ShimaCore

@Suite struct IslandLayoutTests {
    let notch = CGRect(x: 646, y: 924, width: 179, height: 32) // this Mac
    let big = CGRect(x: 537.5, y: 783, width: 396, height: 173)

    @Test func expandedMetricsMatchMockup() {
        #expect(IslandLayout.expanded == IslandShapeMetrics(width: 360, height: 165, bottomRadius: 24, earRadius: 10))
        #expect(IslandLayout.hoverMargin == 8)
    }
    @Test func collapsedMetricsAreNotchSizedWithoutEars() {
        #expect(IslandLayout.collapsedMetrics(notch: notch) == IslandShapeMetrics(width: 179, height: 32, bottomRadius: 9, earRadius: 0))
        #expect(IslandLayout.metrics(for: .collapsed, notch: notch) == IslandLayout.collapsedMetrics(notch: notch))
        #expect(IslandLayout.metrics(for: .expanded, notch: notch) == IslandLayout.expanded)
    }
    @Test func idlePanelIsTheNotch() { #expect(IslandLayout.panelFrame(notch: notch, expanded: false) == notch) }
    @Test func expandedPanelIsCenteredAndFlush() {
        let f = IslandLayout.panelFrame(notch: notch, expanded: true)
        #expect(f == big)
        #expect(f.maxY == 956 && f.midX == notch.midX)
    }
    @Test func idleHotRectInsideBigPanelIsTheNotch() {
        #expect(IslandLayout.hotRect(.idle, notch: notch, panelFrame: big) == CGRect(x: 108.5, y: 141, width: 179, height: 32))
    }
    @Test func idleHotRectInIdlePanelIsWholePanel() {
        #expect(IslandLayout.hotRect(.idle, notch: notch, panelFrame: notch) == CGRect(x: 0, y: 0, width: 179, height: 32))
    }
    @Test func expandedHotRectIsWholePanel() {
        #expect(IslandLayout.hotRect(.expanded, notch: notch, panelFrame: big) == CGRect(x: 0, y: 0, width: 396, height: 173))
    }
    @Test func expandedFrameOnOffsetScreen() { // built-in left of an external main display
        let n = CGRect(x: -824, y: 1024, width: 179, height: 32)
        let f = IslandLayout.panelFrame(notch: n, expanded: true)
        #expect(f.midX == n.midX && f.maxY == 1056 && f.size == big.size)
    }
    @Test func virtualHotZoneExpands() {
        let n = CGRect(x: 620, y: 868, width: 200, height: 32)
        #expect(IslandLayout.panelFrame(notch: n, expanded: true) == CGRect(x: 522, y: 727, width: 396, height: 173))
    }
    @Test @MainActor func appStateStartsCollapsed() { #expect(AppState().mode == .collapsed) }
}
