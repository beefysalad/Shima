import CoreGraphics

/// A snapshot of one display, free of AppKit types so selection is unit-testable.
public struct DisplayDescriptor: Equatable, Sendable {
    public let id: UInt32
    public let isBuiltIn: Bool
    public let frame: CGRect
    public let safeAreaInsetTop: CGFloat
    public let auxiliaryTopLeft: CGRect?
    public let auxiliaryTopRight: CGRect?

    public init(
        id: UInt32, isBuiltIn: Bool, frame: CGRect, safeAreaInsetTop: CGFloat,
        auxiliaryTopLeft: CGRect?, auxiliaryTopRight: CGRect?
    ) {
        self.id = id
        self.isBuiltIn = isBuiltIn
        self.frame = frame
        self.safeAreaInsetTop = safeAreaInsetTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
    }

    private var physicalNotch: CGRect? {
        NotchGeometry.physicalNotchRect(
            screenFrame: frame, safeAreaInsetTop: safeAreaInsetTop,
            auxiliaryTopLeft: auxiliaryTopLeft, auxiliaryTopRight: auxiliaryTopRight)
    }

    /// The physical notch, or the virtual hot zone on a built-in display without one.
    public var notchRect: CGRect {
        NotchGeometry.notchRect(
            screenFrame: frame, safeAreaInsetTop: safeAreaInsetTop,
            auxiliaryTopLeft: auxiliaryTopLeft, auxiliaryTopRight: auxiliaryTopRight)
    }

    public var hasNotch: Bool { physicalNotch != nil }
}

public enum DisplaySelector {
    /// The first built-in display, else `nil`. Shima never falls back to an external or main display.
    public static func target(_ displays: [DisplayDescriptor]) -> DisplayDescriptor? {
        displays.first { $0.isBuiltIn }
    }
}
