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
    public static let expanded = IslandShapeMetrics(width: 720, height: 330, bottomRadius: 36, earRadius: 14)
    public static let collapsedBottomRadius: CGFloat = 9
    public static let hoverMargin: CGFloat = 8

    public static func collapsedMetrics(notch: CGRect) -> IslandShapeMetrics {
        IslandShapeMetrics(width: notch.width, height: notch.height, bottomRadius: collapsedBottomRadius, earRadius: 0)
    }

    public static func metrics(for mode: IslandMode, notch: CGRect) -> IslandShapeMetrics {
        switch mode {
        case .collapsed: collapsedMetrics(notch: notch)
        case .expanded: expanded
        }
    }

    public static func panelFrame(notch: CGRect, expanded: Bool) -> CGRect {
        guard expanded else { return notch }
        let width = Self.expanded.width + 2 * Self.expanded.earRadius + 2 * hoverMargin
        let height = Self.expanded.height + hoverMargin
        return CGRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height)
    }

    public static func hotRect(_ region: HotRegion, notch: CGRect, panelFrame: CGRect) -> CGRect {
        switch region {
        case .idle:
            notch.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
        case .expanded:
            CGRect(origin: .zero, size: panelFrame.size)
        }
    }
}
