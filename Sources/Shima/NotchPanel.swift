import AppKit

/// Borderless, non-activating panel that hosts the pill. Never activates the app (design doc 6.4).
final class NotchPanel: NSPanel {
    static let islandLevel: NSWindow.Level = .statusBar

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        level = Self.islandLevel
        animationBehavior = .none
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
