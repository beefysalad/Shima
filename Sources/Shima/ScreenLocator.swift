import AppKit
import ShimaCore

@MainActor
enum ScreenLocator {
    /// Built-in display if present (the one with the notch), else the main screen.
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else { return false }
            return CGDisplayIsBuiltin(id) != 0
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func notchRect(on screen: NSScreen) -> CGRect {
        NotchGeometry.notchRect(
            screenFrame: screen.frame,
            safeAreaInsetTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea)
    }
}
