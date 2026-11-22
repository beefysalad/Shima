import AppKit
import SwiftUI

/// Spike 4 `buttonFirstMouse`: the first click on the non-key, non-activating panel
/// must reach the SwiftUI buttons instead of being swallowed as a window-activating click.
final class ClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
