@MainActor public protocol DeviceClient: AnyObject {
    var onConnect: (@MainActor (DeviceEvent) -> Void)? { get set }
    func start()
    func stop()
}
