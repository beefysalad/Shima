public enum IslandTab: String, CaseIterable, Hashable, Sendable {
    case music, camera
}

public enum CameraEffect: Equatable, Sendable {
    case requestPermission
    case setRunning(Bool)
}

/// Pure lifecycle reducer. `isRunning` is the requested session state, not hardware status.
public struct CameraModel: Equatable, Sendable {
    public private(set) var permission: CameraPermission
    public private(set) var isRunning = false
    public private(set) var mode: IslandMode = .collapsed
    public private(set) var tab: IslandTab = .music
    public private(set) var screenAvailable = true
    private var permissionRequested = false
    private var terminated = false

    public init(permission: CameraPermission = .notDetermined) {
        self.permission = permission
    }

    public mutating func setContext(mode: IslandMode, tab: IslandTab, screenAvailable: Bool, permission: CameraPermission? = nil) -> [CameraEffect] {
        if let permission { self.permission = permission }
        self.mode = mode
        self.tab = tab
        self.screenAvailable = screenAvailable
        return reconcile()
    }

    public mutating func setPermission(_ permission: CameraPermission) -> [CameraEffect] {
        self.permission = permission
        return reconcile()
    }

    public mutating func shutdown() -> [CameraEffect] {
        terminated = true
        return reconcile()
    }

    private mutating func reconcile() -> [CameraEffect] {
        let visible = mode == .expanded && tab == .camera && screenAvailable && !terminated
        var effects: [CameraEffect] = []
        if visible && permission == .notDetermined && !permissionRequested {
            permissionRequested = true
            effects.append(.requestPermission)
        }
        let shouldRun = visible && permission == .authorized
        if shouldRun != isRunning {
            isRunning = shouldRun
            effects.append(.setRunning(shouldRun))
        }
        return effects
    }
}
