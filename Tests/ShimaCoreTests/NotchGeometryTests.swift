import CoreGraphics
import Testing
@testable import ShimaCore

@Suite struct NotchGeometryTests {
    // 14" MacBook Pro-like: 1512x982 points, 32pt inset, notch roughly 185pt wide.
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func notchIsGapBetweenAuxiliaryAreas() {
        let left = CGRect(x: 0, y: 950, width: 663, height: 32)
        let right = CGRect(x: 849, y: 950, width: 663, height: 32)
        let r = NotchGeometry.notchRect(screenFrame: screen, safeAreaInsetTop: 32,
                                        auxiliaryTopLeft: left, auxiliaryTopRight: right)
        #expect(r == CGRect(x: 663, y: 950, width: 186, height: 32))
    }

    @Test func notchOnOffsetScreenUsesScreenTop() {
        let frame = CGRect(x: -1512, y: 100, width: 1512, height: 982)
        let left = CGRect(x: -1512, y: 1050, width: 663, height: 32)
        let right = CGRect(x: -663, y: 1050, width: 663, height: 32)
        let r = NotchGeometry.notchRect(screenFrame: frame, safeAreaInsetTop: 32,
                                        auxiliaryTopLeft: left, auxiliaryTopRight: right)
        #expect(r.maxY == frame.maxY)
        #expect(r.minX == -849 && r.width == 186)
    }

    @Test func noNotchFallsBackToCentredVirtualNotch() {
        let r = NotchGeometry.notchRect(screenFrame: screen, safeAreaInsetTop: 0,
                                        auxiliaryTopLeft: nil, auxiliaryTopRight: nil)
        #expect(r == CGRect(x: 656, y: 950, width: 200, height: 32))
    }

    @Test func degenerateAuxiliaryAreasFallBack() {
        let a = CGRect(x: 0, y: 950, width: 800, height: 32)
        let b = CGRect(x: 700, y: 950, width: 812, height: 32) // overlaps: no gap
        let r = NotchGeometry.notchRect(screenFrame: screen, safeAreaInsetTop: 32,
                                        auxiliaryTopLeft: a, auxiliaryTopRight: b)
        #expect(r.size == NotchGeometry.virtualNotchSize)
    }

    @Test func pillExtendsPastNotchAndStaysFlushWithTop() {
        let notch = CGRect(x: 663, y: 950, width: 186, height: 32)
        let p = NotchGeometry.pillFrame(notch: notch)
        #expect(p.maxY == notch.maxY)
        #expect(p.midX == notch.midX)
        #expect(p.width == 186 + 12 && p.height == 32 + 6)
    }
}
