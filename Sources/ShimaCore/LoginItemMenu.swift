public enum LoginItemStatus: Sendable {
    case enabled, notRegistered, requiresApproval, notFound
}

public enum LoginItemAction: Equatable, Sendable {
    case register, unregister, openSettings, none
}

public struct LoginItemMenuState: Equatable, Sendable {
    public let title: String
    public let isOn: Bool
    public let isEnabled: Bool

    public init(title: String, isOn: Bool, isEnabled: Bool) {
        self.title = title
        self.isOn = isOn
        self.isEnabled = isEnabled
    }
}

public enum LoginItemMenu {
    /// Only a copy in /Applications may register: SMAppService records the bundle path, and a dist or
    /// ad-hoc build would leave a stale login item. Pure string check; the app passes `Bundle.main.bundlePath`.
    public static func isInstalledLocation(bundlePath: String) -> Bool {
        bundlePath.hasPrefix("/Applications/")
    }

    /// `notFound` is what SMAppService reports for an app that has never been registered (seen for the
    /// certificate-signed bundle in /Applications), so it stays toggleable until a register attempt fails.
    public static func state(for status: LoginItemStatus, registrationFailed: Bool = false, installed: Bool = true) -> LoginItemMenuState {
        guard installed else {
            return LoginItemMenuState(title: "Launch at login (install to /Applications first)", isOn: status == .enabled, isEnabled: false)
        }
        return switch status {
        case .enabled:
            LoginItemMenuState(title: "Launch at login", isOn: true, isEnabled: true)
        case .notRegistered:
            LoginItemMenuState(title: "Launch at login", isOn: false, isEnabled: true)
        case .requiresApproval:
            LoginItemMenuState(title: "Launch at login (approve in System Settings)", isOn: false, isEnabled: true)
        case .notFound:
            registrationFailed
                ? LoginItemMenuState(title: "Launch at login (unavailable)", isOn: false, isEnabled: false)
                : LoginItemMenuState(title: "Launch at login", isOn: false, isEnabled: true)
        }
    }

    public static func action(for status: LoginItemStatus, registrationFailed: Bool = false, installed: Bool = true) -> LoginItemAction {
        guard installed else { return .none }
        return switch status {
        case .enabled: .unregister
        case .notRegistered: .register
        case .requiresApproval: .openSettings
        case .notFound: registrationFailed ? .none : .register
        }
    }
}
