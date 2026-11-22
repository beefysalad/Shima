@testable import ShimaCore

@MainActor final class FakeLoginItemService: LoginItemService {
    var status: LoginItemStatus
    private(set) var performed: [LoginItemAction] = []
    /// Given the action and the current status: success, and the status afterwards.
    var respond: @MainActor (LoginItemAction, LoginItemStatus) -> (Bool, LoginItemStatus) = { action, status in
        switch action {
        case .register: (true, .enabled)
        case .unregister: (true, .notRegistered)
        case .openSettings, .none: (true, status)
        }
    }

    init(status: LoginItemStatus) { self.status = status }

    func perform(_ action: LoginItemAction) -> Bool {
        performed.append(action)
        let (ok, next) = respond(action, status)
        status = next
        return ok
    }
}
