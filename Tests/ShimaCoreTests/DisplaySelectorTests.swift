import CoreGraphics
import Testing
@testable import ShimaCore

@Suite struct DisplaySelectorTests {
    // This Mac, measured 2026-11-21.
    let thisMac = DisplayDescriptor(id: 1, isBuiltIn: true, frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        safeAreaInsetTop: 32, auxiliaryTopLeft: CGRect(x: 0, y: 924, width: 646, height: 32),
        auxiliaryTopRight: CGRect(x: 825, y: 924, width: 645, height: 32))
    let external = DisplayDescriptor(id: 2, isBuiltIn: false, frame: CGRect(x: 1470, y: 0, width: 2560, height: 1440),
        safeAreaInsetTop: 0, auxiliaryTopLeft: nil, auxiliaryTopRight: nil)
    let oldMacBook = DisplayDescriptor(id: 3, isBuiltIn: true, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        safeAreaInsetTop: 0, auxiliaryTopLeft: nil, auxiliaryTopRight: nil)

    @Test func picksBuiltInEvenWhenNotFirst() { #expect(DisplaySelector.target([external, thisMac]) == thisMac) }
    @Test func externalOnlyMeansNoTarget() { #expect(DisplaySelector.target([external]) == nil) }
    @Test func noDisplaysMeansNoTarget() { #expect(DisplaySelector.target([]) == nil) }
    @Test func thisMacNotch() {
        #expect(thisMac.notchRect == CGRect(x: 646, y: 924, width: 179, height: 32))
        #expect(thisMac.hasNotch)
    }
    @Test func builtInWithoutNotchUsesVirtualHotZone() {
        #expect(oldMacBook.notchRect == CGRect(x: 620, y: 868, width: 200, height: 32))
        #expect(!oldMacBook.hasNotch)
    }
}
