import CoreGraphics

public struct IslandShapeMetrics: Equatable, Sendable {
    public var width: CGFloat
    public var height: CGFloat
    public var bottomRadius: CGFloat
    public var earRadius: CGFloat

    public init(width: CGFloat, height: CGFloat, bottomRadius: CGFloat, earRadius: CGFloat) {
        self.width = width
        self.height = height
        self.bottomRadius = bottomRadius
        self.earRadius = earRadius
    }
}

public enum IslandMode: Equatable, Sendable {
    case collapsed, expanded
}

public enum HotRegion: Equatable, Sendable {
    case idle, expanded
}

public enum IslandLayout {
    public static let expanded = IslandShapeMetrics(width: 360, height: 165, bottomRadius: 24, earRadius: 10)
    public static let collapsedBottomRadius: CGFloat = 9
    public static let hoverMargin: CGFloat = 8
    public static let liveWingWidth: CGFloat = 33

    public static func collapsedMetrics(notch: CGRect, live: Bool = false) -> IslandShapeMetrics {
        IslandShapeMetrics(width: notch.width + (live ? 2 * liveWingWidth : 0), height: notch.height, bottomRadius: collapsedBottomRadius, earRadius: 0)
    }

    public static func metrics(for mode: IslandMode, notch: CGRect, live: Bool = false) -> IslandShapeMetrics {
        switch mode {
        case .collapsed: collapsedMetrics(notch: notch, live: live)
        case .expanded: expanded
        }
    }

    public static func idleFrame(notch: CGRect, live: Bool = false) -> CGRect {
        live ? notch.insetBy(dx: -liveWingWidth, dy: 0) : notch
    }

    public static func panelFrame(notch: CGRect, live: Bool = false, expanded: Bool) -> CGRect {
        guard expanded else { return idleFrame(notch: notch, live: live) }
        let width = Self.expanded.width + 2 * Self.expanded.earRadius + 2 * hoverMargin
        let height = Self.expanded.height + hoverMargin
        return CGRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height)
    }

    public static func hotRect(_ region: HotRegion, notch: CGRect, live: Bool = false, panelFrame: CGRect) -> CGRect {
        switch region {
        case .idle:
            idleFrame(notch: notch, live: live).offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
        case .expanded:
            CGRect(origin: .zero, size: panelFrame.size)
        }
    }
}
