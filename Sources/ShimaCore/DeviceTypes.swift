public enum DeviceKind: String, Sendable, CaseIterable {
    case headphones, earbuds, keyboard, mouse, trackpad, speaker, gamepad, other

    public var symbolName: String {
        switch self {
        case .headphones: "headphones"
        case .earbuds: "airpods.gen3"
        case .keyboard: "keyboard"
        case .mouse: "computermouse"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .speaker: "hifispeaker"
        case .gamepad: "gamecontroller"
        case .other: "wave.3.right"
        }
    }

    /// Rules, in order: name keywords for earbuds first (AirPods report the headphones class), then the class of
    /// device with `minor` as the 6-bit field IOBluetooth reports (spike S1: AirPods major 4 minor 6, Keychron K3
    /// major 5 minor 16), then the remaining name keywords.
    public static func classify(major: Int?, minor: Int?, name: String) -> DeviceKind {
        let name = name.lowercased()
        if name.contains("airpods") || name.contains("buds") { return .earbuds }

        if let major, let minor {
            switch (major, minor) {
            case (4, 5): return .speaker
            case (4, 1), (4, 2), (4, 6): return .headphones
            case (5, 16), (5, 48): return .keyboard
            case (5, 32): return .mouse
            default: break
            }
        }

        if name.contains("keyboard") || name.contains("keychron") { return .keyboard }
        if name.contains("mouse") || name.contains("mx master") { return .mouse }
        if name.contains("trackpad") { return .trackpad }
        if name.contains("controller") || name.contains("dualsense") || name.contains("xbox") { return .gamepad }
        return .other
    }
}

public struct DeviceEvent: Equatable, Sendable {
    public let address: String
    public let name: String
    public let kind: DeviceKind
    public let batteryPercent: Int?

    public init(address: String, name: String, kind: DeviceKind, batteryPercent: Int?) {
        self.address = address
        self.name = name
        self.kind = kind
        self.batteryPercent = batteryPercent
    }
}

public struct DevicePeek: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let batteryText: String?
    public let kind: DeviceKind
    public let duration: Duration

    public init(title: String, subtitle: String, batteryText: String?, kind: DeviceKind, duration: Duration) {
        self.title = title
        self.subtitle = subtitle
        self.batteryText = batteryText
        self.kind = kind
        self.duration = duration
    }
}

public enum PeekItem: Equatable, Sendable {
    case device(DevicePeek)
}
