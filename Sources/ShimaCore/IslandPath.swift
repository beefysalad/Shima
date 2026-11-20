import CoreGraphics

public enum IslandPath {
    /// Builds the island in y-down coordinates, centered at the container's top edge.
    public static func make(in container: CGRect, metrics: IslandShapeMetrics) -> CGPath {
        let width = max(0, metrics.width)
        let height = max(0, metrics.height)
        let ear = min(max(0, metrics.earRadius), height)
        let radius = min(max(0, metrics.bottomRadius), width / 2, max(0, height - ear))
        let left = container.midX - width / 2
        let top = container.minY
        let path = CGMutablePath()
        // Analytic quarter-circle endpoints avoid tangent-arc rounding beyond the bounds.
        let kappa: CGFloat = 4 * (sqrt(2) - 1) / 3
        let earControl = kappa * ear
        let bottomControl = kappa * radius

        path.move(to: CGPoint(x: left - ear, y: top))
        path.addCurve(to: CGPoint(x: left, y: top + ear),
                      control1: CGPoint(x: left - ear + earControl, y: top),
                      control2: CGPoint(x: left, y: top + ear - earControl))
        path.addLine(to: CGPoint(x: left, y: top + height - radius))
        path.addCurve(to: CGPoint(x: left + radius, y: top + height),
                      control1: CGPoint(x: left, y: top + height - radius + bottomControl),
                      control2: CGPoint(x: left + radius - bottomControl, y: top + height))
        path.addLine(to: CGPoint(x: left + width - radius, y: top + height))
        path.addCurve(to: CGPoint(x: left + width, y: top + height - radius),
                      control1: CGPoint(x: left + width - radius + bottomControl, y: top + height),
                      control2: CGPoint(x: left + width, y: top + height - radius + bottomControl))
        path.addLine(to: CGPoint(x: left + width, y: top + ear))
        path.addCurve(to: CGPoint(x: left + width + ear, y: top),
                      control1: CGPoint(x: left + width, y: top + ear - earControl),
                      control2: CGPoint(x: left + width + ear - earControl, y: top))
        path.closeSubpath()
        return path
    }
}
