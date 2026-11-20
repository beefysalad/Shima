import AppKit

/// Panel content view. Reports whether the pointer is inside `hotRect` (view coordinates).
final class HoverTrackingView: NSView {
    var onPointer: (Bool) -> Void = { _ in }
    private var trackingArea: NSTrackingArea?

    var hotRect: CGRect = .zero {
        didSet { rebuildTrackingArea() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildTrackingArea()
    }

    private func rebuildTrackingArea() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: hotRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
        // One-shot read (not a monitor): covers a pointer already inside when the rect changes.
        guard let window else { return }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let p = convert(inWindow, from: nil)
        onPointer(hotRect.contains(p))
    }

    override func mouseEntered(with event: NSEvent) { onPointer(true) }
    override func mouseExited(with event: NSEvent) { onPointer(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
}
