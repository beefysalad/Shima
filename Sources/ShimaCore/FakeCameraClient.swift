@MainActor public final class FakeCameraClient: CameraClient {
    public var permission: CameraPermission
    public var requestResult: CameraPermission?
    public private(set) var requestCount = 0
    public private(set) var startCount = 0
    public private(set) var stopCount = 0
    public private(set) var isRunning = false
    public var onPermissionRequest: (@MainActor () -> Void)?
    public var onRunningChange: (@MainActor (Bool) -> Void)?
    private var pendingPermission: (@MainActor (CameraPermission) -> Void)?

    public init(permission: CameraPermission = .notDetermined, requestResult: CameraPermission? = .authorized) {
        self.permission = permission
        self.requestResult = requestResult
    }

    public func requestPermission(_ completion: @escaping @MainActor (CameraPermission) -> Void) {
        requestCount += 1
        pendingPermission = completion
        onPermissionRequest?()
        if let requestResult { completePermission(requestResult) }
    }

    public func completePermission(_ permission: CameraPermission) {
        self.permission = permission
        let completion = pendingPermission
        pendingPermission = nil
        completion?(permission)
    }

    public func setRunning(_ running: Bool) {
        guard running != isRunning else { return }
        isRunning = running
        if running { startCount += 1 } else { stopCount += 1 }
        onRunningChange?(running)
    }
}
