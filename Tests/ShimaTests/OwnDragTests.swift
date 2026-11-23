import Foundation
import Testing
@testable import Shima

@MainActor @Suite(.serialized) struct OwnDragTests {
    @Test func flagStaysSetWithinMaxAge() {
        var now = Date(timeIntervalSince1970: 1_000)
        OwnDrag.now = { now }
        defer { OwnDrag.active = false; OwnDrag.now = Date.init }
        OwnDrag.active = true
        now = now.addingTimeInterval(OwnDrag.maxAge - 1)
        #expect(OwnDrag.active)
    }

    @Test func flagExpiresAfterMaxAgeSoAMissedEndCallbackCannotRefuseDropsForever() {
        var now = Date(timeIntervalSince1970: 1_000)
        OwnDrag.now = { now }
        defer { OwnDrag.active = false; OwnDrag.now = Date.init }
        OwnDrag.active = true
        now = now.addingTimeInterval(OwnDrag.maxAge + 1)
        #expect(!OwnDrag.active)
    }

    @Test func clearingTheFlagIsImmediate() {
        OwnDrag.active = true
        OwnDrag.active = false
        #expect(!OwnDrag.active)
    }
}
