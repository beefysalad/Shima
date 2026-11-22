@MainActor public final class FakeDeviceClient: DeviceClient {
    public var onConnect: (@MainActor (DeviceEvent) -> Void)?
    public private(set) var startCount = 0
    public private(set) var stopCount = 0

    public init() {}

    public func start() { startCount += 1 }

    public func stop() { stopCount += 1 }

    public func emit(_ event: DeviceEvent) { onConnect?(event) }
}
