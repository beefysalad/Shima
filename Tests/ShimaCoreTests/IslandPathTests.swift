import CoreGraphics
import Testing
@testable import ShimaCore

@Suite struct IslandPathTests {
    let box = CGRect(x: 0, y: 0, width: 764, height: 338) // expanded panel bounds
    var expanded: CGPath { IslandPath.make(in: box, metrics: IslandLayout.expanded) }

    @Test func expandedBoundsIncludeEars() {
        #expect(expanded.boundingBoxOfPath == CGRect(x: 8, y: 0, width: 748, height: 330))
    }
    @Test func earCornerIsFilled() { #expect(expanded.contains(CGPoint(x: 21, y: 1))) }
    @Test func earCircleIsTransparent() { #expect(!expanded.contains(CGPoint(x: 10, y: 12))) }
    @Test func bottomCornerIsRounded() { #expect(!expanded.contains(CGPoint(x: 22.5, y: 329.5))) }
    @Test func middleIsFilled() { #expect(expanded.contains(CGPoint(x: 382, y: 165))) }
    @Test func collapsedFillsTheNotchExactly() {
        let p = IslandPath.make(in: CGRect(x: 0, y: 0, width: 179, height: 32),
            metrics: IslandShapeMetrics(width: 179, height: 32, bottomRadius: 9, earRadius: 0))
        #expect(p.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 179, height: 32))
    }
    @Test func overshootMetricsAreClamped() { // ear > height, radius > half height
        let p = IslandPath.make(in: CGRect(x: 0, y: 0, width: 200, height: 40),
            metrics: IslandShapeMetrics(width: 100, height: 20, bottomRadius: 36, earRadius: 30))
        #expect(p.boundingBoxOfPath == CGRect(x: 30, y: 0, width: 140, height: 20))
    }
    @Test func negativeMetricsGiveEmptyPath() {
        let p = IslandPath.make(in: box, metrics: IslandShapeMetrics(width: -5, height: -1, bottomRadius: -3, earRadius: -2))
        let b = p.boundingBoxOfPath
        #expect(b.isNull || b.width * b.height == 0)
    }
}
