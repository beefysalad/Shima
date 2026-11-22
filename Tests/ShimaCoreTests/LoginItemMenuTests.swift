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

    @Test func installedLocationIsUnderApplications() {
        #expect(LoginItemMenu.isInstalledLocation(bundlePath: "/Applications/Shima.app"))
        #expect(LoginItemMenu.isInstalledLocation(bundlePath: "/Applications/Utilities/Shima.app"))
        #expect(!LoginItemMenu.isInstalledLocation(bundlePath: "/Users/x/Documents/coding/shima/dist/Shima.app"))
        #expect(!LoginItemMenu.isInstalledLocation(bundlePath: "/Applications"))
        #expect(!LoginItemMenu.isInstalledLocation(bundlePath: "/ApplicationsX/Shima.app"))
        #expect(!LoginItemMenu.isInstalledLocation(bundlePath: ""))
    }
    @Test func notInstalledIsDisabledWithHintAndNoAction() {
        for status in [LoginItemStatus.enabled, .notRegistered, .requiresApproval, .notFound] {
            let state = LoginItemMenu.state(for: status, installed: false)
            #expect(state.title == "Launch at login (install to /Applications first)" && !state.isEnabled)
            #expect(state.isOn == (status == .enabled))
            #expect(LoginItemMenu.action(for: status, installed: false) == .none)
        }
    }
}
