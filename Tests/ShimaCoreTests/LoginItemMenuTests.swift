import Testing
@testable import ShimaCore

@Suite struct LoginItemMenuTests {
    @Test func enabledIsChecked() {
        #expect(LoginItemMenu.state(for: .enabled) == LoginItemMenuState(title: "Launch at login", isOn: true, isEnabled: true))
        #expect(LoginItemMenu.action(for: .enabled) == .unregister)
    }
    @Test func notRegisteredIsUnchecked() {
        #expect(LoginItemMenu.state(for: .notRegistered) == LoginItemMenuState(title: "Launch at login", isOn: false, isEnabled: true))
        #expect(LoginItemMenu.action(for: .notRegistered) == .register)
    }
    @Test func requiresApprovalPointsToSettings() {
        #expect(LoginItemMenu.state(for: .requiresApproval) == LoginItemMenuState(title: "Launch at login (approve in System Settings)", isOn: false, isEnabled: true))
        #expect(LoginItemMenu.action(for: .requiresApproval) == .openSettings)
    }
    @Test func notFoundIsRegistrableUntilRegistrationFails() {
        #expect(LoginItemMenu.state(for: .notFound) == LoginItemMenuState(title: "Launch at login", isOn: false, isEnabled: true))
        #expect(LoginItemMenu.action(for: .notFound) == .register)
    }
    @Test func notFoundAfterFailedRegistrationIsDisabled() {
        #expect(LoginItemMenu.state(for: .notFound, registrationFailed: true) == LoginItemMenuState(title: "Launch at login (unavailable)", isOn: false, isEnabled: false))
        #expect(LoginItemMenu.action(for: .notFound, registrationFailed: true) == .none)
    }
}
