/// How the equalizer behaves (Settings window). Stored by raw value in `local.shima` / `equalizerMode`.
public enum EqualizerMode: String, CaseIterable, Equatable, Sendable {
    case animated, whenOpen, off

    public static let `default`: EqualizerMode = .animated

    /// Reads a stored raw value; nil or an unknown value means the default.
    public init(stored: String?) {
        self = stored.flatMap(EqualizerMode.init(rawValue:)) ?? .default
    }

    public var title: String {
        switch self {
        case .animated: "Animated"
        case .whenOpen: "Only when open"
        case .off: "Off"
        }
    }
}

/// The equalizer sits right of the notch: in the live wing while collapsed or peeking, and at the same spot in the
/// open island's top strip while a track is shown. Modes change only whether its bars animate.
public enum EqualizerPolicy {
    public static func isVisible(island: IslandMode, live: Bool, content: NowPlayingContent) -> Bool {
        switch island {
        case .collapsed, .peek: live
        case .expanded: content == .track
        }
    }

    public static func isAnimating(_ mode: EqualizerMode, island: IslandMode, live: Bool,
                                   content: NowPlayingContent, playing: Bool, frozen: Bool) -> Bool {
        guard playing, !frozen, isVisible(island: island, live: live, content: content) else { return false }
        switch mode {
        case .animated: return true
        case .whenOpen: return island == .expanded
        case .off: return false
        }
    }
}
