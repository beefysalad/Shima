import AppKit
import SwiftUI

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
        contentView = NSHostingView(rootView: PillView())
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct PillView: View {
    /// Set SHIMA_DEBUG=1 to tint the pill red so it is visible against the black notch.
    static let debug = ProcessInfo.processInfo.environment["SHIMA_DEBUG"] != nil
    var body: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
            .fill(Self.debug ? Color.red : Color.black)
    }
}
