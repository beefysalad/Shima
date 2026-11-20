import ServiceManagement
import ShimaCore

@MainActor
enum LoginItem {
    static var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .notRegistered
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    static func perform(_ action: LoginItemAction) {
        let service = SMAppService.mainApp
        switch action {
        case .register:
            do { try service.register() } catch {
                Log.menu.error("register failed: \(error.localizedDescription, privacy: .public)")
            }
        case .unregister:
            do { try service.unregister() } catch {
                Log.menu.error("unregister failed: \(error.localizedDescription, privacy: .public)")
            }
        case .openSettings:
            SMAppService.openSystemSettingsLoginItems()
        case .none:
            break
        }
    }
}
