import Foundation

public enum PeekDrop: Equatable, Sendable {
    case disabled, wakeGrace, repeated
}

public enum PeekDecision: Equatable, Sendable {
    case show(DevicePeek)
    case drop(PeekDrop)
}

public struct DevicePeekPolicy: Sendable {
    private var lastWake: Date?
    private var lastShownByAddress: [String: Date] = [:]

    public init() {}

    public mutating func didWake(at date: Date) {
        lastWake = date
    }

    public mutating func decide(_ event: DeviceEvent, now: Date, enabled: Bool) -> PeekDecision {
        guard enabled else { return .drop(.disabled) }
        if let lastWake, (0..<10).contains(now.timeIntervalSince(lastWake)) {
            return .drop(.wakeGrace)
        }

        lastShownByAddress = lastShownByAddress.filter { (0..<5).contains(now.timeIntervalSince($0.value)) }
        guard lastShownByAddress[event.address] == nil else { return .drop(.repeated) }

        lastShownByAddress[event.address] = now
        let name = event.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle: String
        if name.isEmpty {
            subtitle = "Bluetooth device"
        } else if name.count > 40 {
            subtitle = String(name.prefix(39)) + "…"
        } else {
            subtitle = name
        }
        let batteryText = event.batteryPercent.flatMap { (0...100).contains($0) ? "\($0)%" : nil }
        return .show(DevicePeek(
            title: "Connected",
            subtitle: subtitle,
            batteryText: batteryText,
            kind: event.kind,
            duration: .seconds(3)
        ))
    }
}
