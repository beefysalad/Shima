public enum CameraPermission: Equatable, Sendable {
    case notDetermined, authorized, denied
}

/// Calls deliver ordered intent; hardware clients perform session work off the main thread.
@MainActor public protocol CameraClient: AnyObject {
    var permission: CameraPermission { get }
    func requestPermission(_ completion: @escaping @MainActor (CameraPermission) -> Void)
    func setRunning(_ running: Bool)
}
