import Observation

@Observable @MainActor public final class CameraCoordinator {
    public private(set) var model: CameraModel
    @ObservationIgnored private let client: any CameraClient

    public init(client: any CameraClient) {
        self.client = client
        self.model = CameraModel(permission: client.permission)
    }

    public func setContext(mode: IslandMode, tab: IslandTab, screenAvailable: Bool) {
        // Update permission and visibility together: stale authorization must never
        // briefly start a revoked camera when reopening or leaving a hidden context.
        perform(model.setContext(mode: mode, tab: tab, screenAvailable: screenAvailable,
                                 permission: client.permission))
    }

    public func refreshPermission() {
        perform(model.setPermission(client.permission))
    }

    public func shutdown() {
        perform(model.shutdown())
    }

    private func perform(_ effects: [CameraEffect]) {
        for effect in effects {
            switch effect {
            case .requestPermission:
                client.requestPermission { [weak self] permission in
                    guard let self else { return }
                    self.perform(self.model.setPermission(permission))
                }
            case .setRunning(let running):
                client.setRunning(running)
            }
        }
    }
}
