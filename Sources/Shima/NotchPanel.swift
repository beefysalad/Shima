import AppKit
import SwiftUI

/// Borderless, non-activating panel that hosts the pill. Never activates the app (design doc 6.4).
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        contentView = NSHostingView(rootView: PillView())
    }

    // Scaffold only: lets Esc reach the panel after a click. Per design doc 6.4 this goes back to
    // `false` once real interaction lands (true only while a text field is being edited).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { // Esc
        NSApp.terminate(nil)
    }
}

struct PillView: View {
    /// Set SHIMA_DEBUG=1 to tint the pill red so it is visible against the black notch.
    static let debug = ProcessInfo.processInfo.environment["SHIMA_DEBUG"] != nil
    var body: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
            .fill(Self.debug ? Color.red : Color.black)
    }
}
