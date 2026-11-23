import Testing
@testable import ShimaCore

struct ScreenAvailabilityTests {
    @Test func workRequiresAwakeScreenAwakeSystemUnlockedAndActiveSession() {
        for mask in 0..<16 {
            #expect(ScreenAvailability.allowsWork(
                screenAwake: mask & 1 != 0,
                systemAwake: mask & 2 != 0,
                locked: mask & 4 != 0,
                sessionActive: mask & 8 != 0) == (mask == 11))
        }
    }
}
