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
    /// `notFound` is what SMAppService reports for an app that has never been registered (seen for the
    /// certificate-signed bundle in /Applications), so it stays toggleable until a register attempt fails.
    public static func state(for status: LoginItemStatus, registrationFailed: Bool = false) -> LoginItemMenuState {
        switch status {
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

    public static func action(for status: LoginItemStatus, registrationFailed: Bool = false) -> LoginItemAction {
        switch status {
        case .enabled: .unregister
        case .notRegistered: .register
        case .requiresApproval: .openSettings
        case .notFound: registrationFailed ? .none : .register
        }
    }
}
