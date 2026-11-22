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
        #expect(IslandLayout.collapsedMetrics(notch: notch, live: false) == IslandShapeMetrics(width: 179, height: 32, bottomRadius: 9, earRadius: 0))
        #expect(IslandLayout.metrics(for: .collapsed, notch: notch, live: false) == IslandLayout.collapsedMetrics(notch: notch, live: false))
        #expect(IslandLayout.metrics(for: .expanded, notch: notch, live: false) == IslandLayout.expanded)
    }
    @Test func idlePanelIsTheNotch() { #expect(IslandLayout.panelFrame(notch: notch, live: false, expanded: false) == notch) }
    @Test func expandedPanelIsCenteredAndFlush() {
        let f = IslandLayout.panelFrame(notch: notch, live: false, expanded: true)
        #expect(f == big)
        #expect(f.maxY == 956 && f.midX == notch.midX)
    }
    @Test func idleHotRectInsideBigPanelIsTheNotch() {
        #expect(IslandLayout.hotRect(.idle, notch: notch, live: false, panelFrame: big) == CGRect(x: 108.5, y: 141, width: 179, height: 32))
    }
    @Test func idleHotRectInIdlePanelIsWholePanel() {
        #expect(IslandLayout.hotRect(.idle, notch: notch, live: false, panelFrame: notch) == CGRect(x: 0, y: 0, width: 179, height: 32))
    }
    @Test func expandedHotRectIsWholePanel() {
        #expect(IslandLayout.hotRect(.expanded, notch: notch, live: false, panelFrame: big) == CGRect(x: 0, y: 0, width: 396, height: 173))
    }
    @Test func expandedFrameOnOffsetScreen() { // built-in left of an external main display
        let n = CGRect(x: -824, y: 1024, width: 179, height: 32)
        let f = IslandLayout.panelFrame(notch: n, live: false, expanded: true)
        #expect(f.midX == n.midX && f.maxY == 1056 && f.size == big.size)
    }
    @Test func virtualHotZoneExpands() {
        let n = CGRect(x: 620, y: 868, width: 200, height: 32)
        #expect(IslandLayout.panelFrame(notch: n, live: false, expanded: true) == CGRect(x: 522, y: 727, width: 396, height: 173))
    }
    @Test @MainActor func appStateStartsCollapsed() { #expect(AppState().mode == .collapsed) }
    let live = CGRect(x: 613, y: 924, width: 245, height: 32)

    @Test func liveWingsAre33() { #expect(IslandLayout.liveWingWidth == 33) }
    @Test func liveIdleFrameOnThisMac() {
        #expect(IslandLayout.idleFrame(notch: notch, live: true) == live)
        #expect(IslandLayout.panelFrame(notch: notch, live: true, expanded: false) == live)
    }
    @Test func liveFrameClearsFirstStatusItem() { #expect(IslandLayout.idleFrame(notch: notch, live: true).maxX == 858) } // item at 860
    @Test func notLiveIdleFrameIsTheNotch() { #expect(IslandLayout.idleFrame(notch: notch, live: false) == notch) }
    @Test func expandedPanelIgnoresLive() { #expect(IslandLayout.panelFrame(notch: notch, live: true, expanded: true) == big) }
    @Test func liveCollapsedMetrics() {
        #expect(IslandLayout.collapsedMetrics(notch: notch, live: true) == IslandShapeMetrics(width: 245, height: 32, bottomRadius: 9, earRadius: 0))
        #expect(IslandLayout.metrics(for: .expanded, notch: notch, live: true) == IslandLayout.expanded)
        #expect(IslandLayout.metrics(for: .collapsed, notch: notch, live: true) == IslandLayout.collapsedMetrics(notch: notch, live: true))
    }
    @Test func liveIdleHotRectInIdlePanel() {
        #expect(IslandLayout.hotRect(.idle, notch: notch, live: true, panelFrame: live) == CGRect(x: 0, y: 0, width: 245, height: 32))
    }
    @Test func liveIdleHotRectInsideBigPanel() {
        #expect(IslandLayout.hotRect(.idle, notch: notch, live: true, panelFrame: big) == CGRect(x: 75.5, y: 141, width: 245, height: 32))
    }
    @Test func liveOnVirtualHotZone() {
        let n = CGRect(x: 620, y: 868, width: 200, height: 32)
        #expect(IslandLayout.idleFrame(notch: n, live: true) == CGRect(x: 587, y: 868, width: 266, height: 32))
    }

    @Test func liveOnHotRectIncludesWingBeforeAppliedStateChanges() {
        let appliedLive = false
        let targetLive = true
        let resizedPanel = IslandLayout.panelFrame(notch: notch, live: targetLive, expanded: false)
        let wing = CGPoint(x: 630 - resizedPanel.minX, y: 940 - resizedPanel.minY)
        let targetHotRect = IslandLayout.hotRect(.idle, notch: notch, live: targetLive, panelFrame: resizedPanel)
        let appliedHotRect = IslandLayout.hotRect(.idle, notch: notch, live: appliedLive, panelFrame: resizedPanel)
        #expect(resizedPanel == live)
        #expect(targetHotRect == CGRect(origin: .zero, size: resizedPanel.size))
        #expect(targetHotRect.contains(wing))
        #expect(!appliedHotRect.contains(wing))
    }

    @Test func liveOffHotRectExcludesWingBeforeAppliedStateChanges() {
        let appliedLive = true
        let targetLive = false
        // The hot region can change before the old wing frame has shrunk.
        let panelBeforeShrink = IslandLayout.panelFrame(notch: notch, live: appliedLive, expanded: false)
        let wing = CGPoint(x: 630 - panelBeforeShrink.minX, y: 940 - panelBeforeShrink.minY)
        let targetHotRect = IslandLayout.hotRect(.idle, notch: notch, live: targetLive, panelFrame: panelBeforeShrink)
        let appliedHotRect = IslandLayout.hotRect(.idle, notch: notch, live: appliedLive, panelFrame: panelBeforeShrink)
        #expect(targetHotRect == CGRect(x: 33, y: 0, width: 179, height: 32))
        #expect(!targetHotRect.contains(wing))
        #expect(appliedHotRect.contains(wing))
        #expect(targetHotRect.contains(CGPoint(x: notch.midX - panelBeforeShrink.minX, y: 16)))
    }
}
