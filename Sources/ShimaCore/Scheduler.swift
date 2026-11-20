@MainActor public protocol ScheduledTask: AnyObject {
    func cancel()
}

@MainActor public protocol Scheduler: AnyObject {
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask
}

public struct HoverTiming: Equatable, Sendable {
    public var dwell: Duration
    public var leaveDebounce: Duration

    public init(dwell: Duration, leaveDebounce: Duration) {
        self.dwell = dwell
        self.leaveDebounce = leaveDebounce
    }

    public static let standard = HoverTiming(dwell: .milliseconds(80), leaveDebounce: .milliseconds(300))
}
