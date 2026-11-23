import Foundation
import Testing
@testable import Shima
@testable import ShimaCore

@MainActor struct ServiceLifecycleTests {
    /// Invoke only this fixture's existing notification selectors. Posting distributed
    /// lock or sleep notifications could affect another process and is deliberately avoided.
    private func invoke(_ object: NSObject, _ selector: String) throws {
        let selector = NSSelectorFromString(selector)
        try #require(object.responds(to: selector))
        _ = object.perform(selector)
    }

    @Test func fakeCameraUsesAllFourAvailabilityFlags() throws {
        for mask in 0..<16 {
            let state = AppState()
            let service = CameraService(state: state, environment: ["SHIMA_FAKE_CAMERA": "1"])
            defer { service.shutdown() }
            let fake = try #require(service.fake)
            #expect(service.capture == nil)
            try invoke(service, mask & 1 != 0 ? "woke" : "slept")
            try invoke(service, mask & 2 != 0 ? "systemWoke" : "systemSlept")
            try invoke(service, mask & 4 != 0 ? "screenLocked" : "screenUnlocked")
            try invoke(service, mask & 8 != 0 ? "sessionBecameActive" : "sessionResigned")
            state.mode = .expanded
            state.selectedTab = .camera
            #expect(fake.isRunning == (mask == 11), "Availability mask: \(mask)")
            #expect(fake.requestCount == 0)
            state.selectedTab = .music
            #expect(!fake.isRunning)
        }
    }

    @Test func fakeCalendarUsesAllFourAvailabilityFlags() throws {
        for mask in 0..<16 {
            let state = AppState()
            let service = CalendarService(state: state, environment: ["SHIMA_FAKE_CALENDAR": "1"])
            defer { service.shutdown() }
            try invoke(service, mask & 1 != 0 ? "screenWoke" : "screenSlept")
            try invoke(service, mask & 2 != 0 ? "systemWoke" : "systemSlept")
            try invoke(service, mask & 4 != 0 ? "screenLocked" : "screenUnlocked")
            try invoke(service, mask & 8 != 0 ? "sessionBecameActive" : "sessionResigned")
            state.mode = .expanded
            state.selectedTab = .calendar
            #expect(service.coordinator.model.isVisible == (mask == 11), "Availability mask: \(mask)")
            state.selectedTab = .music
            #expect(!service.coordinator.model.isVisible)
        }
    }

    @Test func cameraShutdownStopsAndDetachesFromTabChanges() throws {
        let state = AppState()
        let service = CameraService(state: state, environment: ["SHIMA_FAKE_CAMERA": "1"])
        let fake = try #require(service.fake)
        for selector in ["woke", "systemWoke", "screenUnlocked", "sessionBecameActive"] {
            try invoke(service, selector)
        }
        state.mode = .expanded
        state.selectedTab = .camera
        #expect(fake.isRunning)
        service.shutdown()
        #expect(!fake.isRunning)
        let starts = fake.startCount
        state.selectedTab = .music
        state.selectedTab = .camera
        #expect(!fake.isRunning && fake.startCount == starts)
    }

    @Test func calendarShutdownStopsAndDetachesFromTabChanges() throws {
        let state = AppState()
        let service = CalendarService(state: state, environment: ["SHIMA_FAKE_CALENDAR": "1"])
        for selector in ["screenWoke", "systemWoke", "screenUnlocked", "sessionBecameActive"] {
            try invoke(service, selector)
        }
        state.mode = .expanded
        state.selectedTab = .calendar
        #expect(service.coordinator.model.isVisible)
        service.shutdown()
        #expect(!service.coordinator.model.isVisible)
        state.selectedTab = .music
        state.selectedTab = .calendar
        #expect(!service.coordinator.model.isVisible)
    }
}
