import Foundation
import Observation
import Testing
@testable import ShimaCore

@MainActor final class SettingsTaps {
    var urls: [URL] = []
    var quits = 0
    var signingReads = 0
    var modes: [EqualizerMode] = []
}

@Suite @MainActor struct SettingsModelTests {
    struct Rig {
        let model: SettingsModel
        let state: AppState
        let storage: InMemoryPreferenceStorage
        let login: FakeLoginItemService
        let taps: SettingsTaps
    }

    func make(stored: [String: String] = [:], login status: LoginItemStatus = .notFound,
              signing: SigningSummary = .adHoc, bundlePath: String = "/Applications/Shima.app") -> Rig {
        let state = AppState(), storage = InMemoryPreferenceStorage(stored)
        let login = FakeLoginItemService(status: status), taps = SettingsTaps()
        let model = SettingsModel(
            state: state, store: SettingsStore(storage: storage), loginItems: login, versionText: "Version 0.0.1 (1)", bundlePath: bundlePath,
            readSigning: { taps.signingReads += 1; return signing },
            now: { ISO8601DateFormatter().date(from: "2026-11-22T00:00:00Z")! })
        model.onOpenURL = { taps.urls.append($0) }
        model.onQuit = { taps.quits += 1 }
        model.onEqualizerModeChange = { taps.modes.append($0) }
        return Rig(model: model, state: state, storage: storage, login: login, taps: taps)
    }

    @Test func devicePopupsFollowTheStoredValueAndChanges() {
        let defaults = make()
        #expect(defaults.model.devicePopupsEnabled && defaults.state.devicePopupsEnabled)
        #expect(defaults.state.peek == nil)

        let r = make(stored: ["devicePopups": "off"])
        #expect(!r.model.devicePopupsEnabled && !r.state.devicePopupsEnabled)
        var changes: [Bool] = []
        r.model.onDevicePopupsChange = { enabled in
            #expect(enabled && r.model.devicePopupsEnabled && r.state.devicePopupsEnabled)
            #expect(r.storage.values["devicePopups"] == "on")
            changes.append(enabled)
        }
        r.model.setDevicePopupsEnabled(true)
        r.model.setDevicePopupsEnabled(true)
        #expect(changes == [true] && r.storage.writes == 1)
    }

    @Test func initLoadsStoredModeIntoState() {
        let r = make(stored: ["equalizerMode": "off"])
        #expect(r.model.equalizerMode == .off && r.state.equalizerMode == .off && r.storage.writes == 0)
    }
    @Test func setEqualizerModeSavesAndUpdatesState() {
        let r = make()
        r.model.setEqualizerMode(.whenOpen)
        r.model.setEqualizerMode(.whenOpen)
        #expect(r.storage.values["equalizerMode"] == "whenOpen" && r.storage.writes == 1)
        #expect(r.state.equalizerMode == .whenOpen && r.model.equalizerMode == .whenOpen && r.taps.modes == [.whenOpen])
    }
    @Test func refreshReadsLoginStatus() {
        let r = make(login: .notRegistered)
        r.login.status = .enabled
        r.model.refresh()
        #expect(r.model.loginItemStatus == .enabled && r.model.loginItem.isOn)
    }
    @Test func toggleRegistersFromNotFound() {
        let r = make(login: .notFound)
        #expect(r.model.toggleLaunchAtLogin() == LoginItemToggle(from: .notFound, action: .register, succeeded: true, after: .enabled))
        #expect(r.login.performed == [.register])
        #expect(r.model.loginItem == LoginItemMenuState(title: "Launch at login", isOn: true, isEnabled: true))
    }
    @Test func toggleUnregistersWhenEnabled() {
        let r = make(login: .enabled)
        #expect(r.model.toggleLaunchAtLogin() == LoginItemToggle(from: .enabled, action: .unregister, succeeded: true, after: .notRegistered))
        #expect(!r.model.loginItem.isOn)
    }
    @Test func failedRegisterMakesItUnavailable() {
        let r = make(login: .notFound)
        r.login.respond = { _, status in (false, status) }
        #expect(r.model.toggleLaunchAtLogin() == LoginItemToggle(from: .notFound, action: .register, succeeded: false, after: .notFound))
        #expect(r.model.loginRegistrationFailed)
        #expect(r.model.loginItem == LoginItemMenuState(title: "Launch at login (unavailable)", isOn: false, isEnabled: false))
        #expect(r.model.toggleLaunchAtLogin().action == .none && r.login.performed == [.register])
    }
    @Test func requiresApprovalOpensSystemSettings() {
        let r = make(login: .requiresApproval)
        #expect(r.model.toggleLaunchAtLogin() == LoginItemToggle(from: .requiresApproval, action: .openSettings, succeeded: true, after: .requiresApproval))
        #expect(r.login.performed == [.openSettings])
    }
    @Test func spotifyRowFollowsAppState() {
        let r = make()
        #expect(r.model.spotifyRow.kind == .notRunning)
        r.state.spotifyAvailability = .permissionDenied
        #expect(r.model.spotifyRow == SettingsText.spotifyRow(.permissionDenied))
    }
    @Test func openAutomationSettingsUsesExactURL() {
        let r = make()
        r.model.openAutomationSettings()
        #expect(r.taps.urls.map(\.absoluteString) == ["x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"])
    }
    @Test func quitCallsHandler() {
        let r = make()
        r.model.quit()
        #expect(r.taps.quits == 1)
    }
    @Test func signingIsReadOnceOnFirstRefresh() {
        let r = make(signing: .adHoc)
        #expect(r.model.signingText == "" && r.taps.signingReads == 0)
        r.model.refresh()
        r.model.refresh()
        #expect(r.taps.signingReads == 1 && r.model.signingText == "Signed ad hoc (no certificate)")
    }

    @Test func toggleUsesFreshServiceStatusInsteadOfCachedStatus() {
        let r = make(login: .notRegistered)
        r.login.status = .enabled
        #expect(r.model.loginItemStatus == .notRegistered)
        let result = r.model.toggleLaunchAtLogin()
        #expect(result == LoginItemToggle(from: .enabled, action: .unregister,
                                         succeeded: true, after: .notRegistered))
        #expect(r.login.performed == [.unregister])
        #expect(r.model.loginItemStatus == .notRegistered)
    }

    @Test func failedUnregisterPreservesEnabledControlsAndAllowsRetry() {
        let r = make(login: .enabled)
        r.login.respond = { _, status in (false, status) }
        #expect(r.model.toggleLaunchAtLogin() == LoginItemToggle(
            from: .enabled, action: .unregister, succeeded: false, after: .enabled))
        #expect(r.model.loginRegistrationFailed)
        #expect(r.model.loginItem == LoginItemMenuState(title: "Launch at login", isOn: true, isEnabled: true))
        r.login.respond = { _, _ in (true, .notRegistered) }
        #expect(r.model.toggleLaunchAtLogin().succeeded)
        #expect(r.login.performed == [.unregister, .unregister])
        #expect(r.model.loginItem == LoginItemMenuState(title: "Launch at login", isOn: false, isEnabled: true))
    }

    @Test func refreshDoesNotReloadStoredMode() {
        let r = make(stored: ["equalizerMode": "off"])
        r.storage.setString("whenOpen", forKey: "equalizerMode")
        r.model.refresh()
        #expect(r.model.equalizerMode == .off)
        #expect(r.state.equalizerMode == .off)
        #expect(r.storage.values["equalizerMode"] == "whenOpen")
        #expect(r.storage.writes == 1)
    }

    @Test func modeCallbackSeesPersistedModeAndUpdatedState() {
        let r = make()
        r.model.onEqualizerModeChange = { mode in
            #expect(mode == .off)
            #expect(r.model.equalizerMode == mode)
            #expect(r.state.equalizerMode == mode)
            #expect(r.storage.values["equalizerMode"] == mode.rawValue)
            r.taps.modes.append(mode)
        }
        r.model.setEqualizerMode(.off)
        #expect(r.taps.modes == [.off])
    }

    @Test func loginItemObservationTracksStatusRefresh() async {
        let r = make(login: .notRegistered)
        await confirmation("login item invalidated") { changed in
            withObservationTracking {
                #expect(!r.model.loginItem.isOn)
            } onChange: {
                changed()
            }
            r.login.status = .enabled
            r.model.refresh()
        }
        #expect(r.model.loginItem.isOn)
    }

    @Test func spotifyObservationTracksUnderlyingStateWithoutRefresh() async {
        let r = make()
        await confirmation("Spotify row invalidated") { changed in
            withObservationTracking {
                #expect(r.model.spotifyRow.kind == .notRunning)
            } onChange: {
                changed()
            }
            r.state.spotifyAvailability = .permissionDenied
        }
        #expect(r.model.spotifyRow.kind == .permissionDenied)
    }

    @Test func devBuildCannotToggleLaunchAtLogin() {
        let r = make(login: .notFound, bundlePath: "/Users/x/shima/dist/Shima.app")
        #expect(!r.model.loginItem.isEnabled)
        #expect(r.model.loginItem.title == "Launch at login (install to /Applications first)")
        let t = r.model.toggleLaunchAtLogin()
        #expect(t.action == .none && r.login.performed.isEmpty)
    }
}
