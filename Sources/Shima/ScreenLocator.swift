import AppKit
import ShimaCore

@MainActor
enum ScreenLocator {
    private static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")

    private static func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value
    }

    static func descriptors() -> [DisplayDescriptor] {
        NSScreen.screens.compactMap { screen in
            guard let id = displayID(of: screen) else { return nil }
            return DisplayDescriptor(
                id: id,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                frame: screen.frame,
                safeAreaInsetTop: screen.safeAreaInsets.top,
                auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
                auxiliaryTopRight: screen.auxiliaryTopRightArea)
        }
    }

    /// The built-in display, or `nil` when there is none (no main-screen fallback).
    static func target() -> DisplayDescriptor? {
        DisplaySelector.target(descriptors())
    }

    static func screen(id: UInt32) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }
}
