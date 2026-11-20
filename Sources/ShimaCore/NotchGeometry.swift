import CoreGraphics

/// Pure geometry for locating the notch and sizing the pill. No AppKit types, so it is unit-testable.
/// All rects are in AppKit screen coordinates (origin bottom-left).
public enum NotchGeometry {
    /// Size of the "virtual notch" used on displays without a physical one (design doc 6.5 / M0).
    public static let virtualNotchSize = CGSize(width: 200, height: 32)

    /// How far the idle pill extends past the notch on each side and below it. Zero keeps it flush,
    /// so it is invisible until it expands or shows a live indicator. Set SHIMA_DEBUG=1 to see it.
    public static let pillOverhang: CGFloat = 0

    /// The physical notch: the screen's top strip between `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`,
    /// `safeAreaInsetTop` tall. `nil` when the display has no notch (no inset, or missing/degenerate
    /// auxiliary areas).
    public static func physicalNotchRect(
        screenFrame: CGRect,
        safeAreaInsetTop: CGFloat,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?
    ) -> CGRect? {
        guard safeAreaInsetTop > 0,
              let left = auxiliaryTopLeft, let right = auxiliaryTopRight,
              right.minX > left.maxX else { return nil }
        return CGRect(
            x: left.maxX,
            y: screenFrame.maxY - safeAreaInsetTop,
            width: right.minX - left.maxX,
            height: safeAreaInsetTop
        )
    }

    /// The notch rect, or a virtual notch centred at the top of the screen when the display has none.
    public static func notchRect(
        screenFrame: CGRect,
        safeAreaInsetTop: CGFloat,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?
    ) -> CGRect {
        physicalNotchRect(
            screenFrame: screenFrame, safeAreaInsetTop: safeAreaInsetTop,
            auxiliaryTopLeft: auxiliaryTopLeft, auxiliaryTopRight: auxiliaryTopRight
        ) ?? CGRect(
            x: screenFrame.midX - virtualNotchSize.width / 2,
            y: screenFrame.maxY - virtualNotchSize.height,
            width: virtualNotchSize.width,
            height: virtualNotchSize.height
        )
    }

    /// Frame of the static pill: the notch rect widened by `pillOverhang` on both sides and
    /// extended `pillOverhang` below, flush with the top edge of the screen.
    public static func pillFrame(notch: CGRect) -> CGRect {
        CGRect(
            x: notch.minX - pillOverhang,
            y: notch.minY - pillOverhang,
            width: notch.width + 2 * pillOverhang,
            height: notch.height + pillOverhang
        )
    }
}
