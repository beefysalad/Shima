import Foundation
import Observation

@MainActor public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    /// Returns false only when register or unregister threw.
    func perform(_ action: LoginItemAction) -> Bool
}

public enum SettingsEntry: String, Sendable {
    case reopen, gear, menu
}

public struct LoginItemToggle: Equatable, Sendable {
    public let from: LoginItemStatus
    public let action: LoginItemAction
    public let succeeded: Bool
    public let after: LoginItemStatus

    public init(from: LoginItemStatus, action: LoginItemAction, succeeded: Bool, after: LoginItemStatus) {
        self.from = from
        self.action = action
        self.succeeded = succeeded
        self.after = after
    }
}

/// The settings shared by the status menu and the Settings window. No polling: `refresh()` runs when the
/// window or the menu opens; the Spotify row follows `AppState` through Observation.
@Observable @MainActor public final class SettingsModel {
    public private(set) var loginItemStatus: LoginItemStatus
    public private(set) var loginRegistrationFailed = false
    public private(set) var equalizerMode: EqualizerMode
    public private(set) var signingText = ""
    public let versionText: String

    public var loginItem: LoginItemMenuState {
        LoginItemMenu.state(for: loginItemStatus, registrationFailed: loginRegistrationFailed)
    }
    public var spotifyRow: SpotifyStatusRow { SettingsText.spotifyRow(state.spotifyAvailability) }

    @ObservationIgnored public var onOpenURL: (@MainActor (URL) -> Void)?
    @ObservationIgnored public var onQuit: (@MainActor () -> Void)?
    @ObservationIgnored public var onEqualizerModeChange: (@MainActor (EqualizerMode) -> Void)?

    @ObservationIgnored private let state: AppState
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let loginItems: LoginItemService
    @ObservationIgnored private let readSigning: @MainActor () -> SigningSummary
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var signingRead = false

    public init(state: AppState, store: SettingsStore, loginItems: LoginItemService, versionText: String,
                readSigning: @escaping @MainActor () -> SigningSummary,
                now: @escaping @MainActor () -> Date = { Date() }) {
        self.state = state
        self.store = store
        self.loginItems = loginItems
        self.versionText = versionText
        self.readSigning = readSigning
        self.now = now
        self.loginItemStatus = loginItems.status
        let mode = store.equalizerMode
        self.equalizerMode = mode
        state.equalizerMode = mode
    }

    public func refresh() {
        loginItemStatus = loginItems.status
        if !signingRead {
            signingRead = true
            signingText = SettingsText.signing(readSigning(), now: now())
        }
    }

    @discardableResult
    public func toggleLaunchAtLogin() -> LoginItemToggle {
        let from = loginItems.status
        let action = LoginItemMenu.action(for: from, registrationFailed: loginRegistrationFailed)
        var succeeded = true
        if action != .none {
            succeeded = loginItems.perform(action)
            if !succeeded { loginRegistrationFailed = true }
        }
        let after = loginItems.status
        loginItemStatus = after
        return LoginItemToggle(from: from, action: action, succeeded: succeeded, after: after)
    }

    public func setEqualizerMode(_ mode: EqualizerMode) {
        store.setEqualizerMode(mode)
        guard mode != equalizerMode else { return }
        equalizerMode = mode
        state.equalizerMode = mode
        onEqualizerModeChange?(mode)
    }

    public func openAutomationSettings() { onOpenURL?(SettingsLinks.automation) }

    public func quit() { onQuit?() }
}
