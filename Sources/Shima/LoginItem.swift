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

    /// Returns false only when register or unregister threw.
    @discardableResult
    static func perform(_ action: LoginItemAction) -> Bool {
        let service = SMAppService.mainApp
        switch action {
        case .register:
            do { try service.register() } catch {
                Log.menu.error("register failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case .unregister:
            do { try service.unregister() } catch {
                Log.menu.error("unregister failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case .openSettings:
            SMAppService.openSystemSettingsLoginItems()
        case .none:
            break
        }
        return true
    }
}

@MainActor
final class SystemLoginItemService: LoginItemService {
    var status: LoginItemStatus { LoginItem.status }
    func perform(_ action: LoginItemAction) -> Bool { LoginItem.perform(action) }
}
