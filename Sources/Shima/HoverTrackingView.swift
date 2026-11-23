import AppKit
import ShimaCore

/// Panel content view. Reports whether the pointer is inside `hotRect` (view coordinates).
final class HoverTrackingView: NSView {
    var onPointer: (Bool) -> Void = { _ in }
    var onDragEvent: (ShelfDragEvent) -> Void = { _ in }
    var onDrop: ([DroppedEntry]) -> ShelfAddResult = { _ in ShelfAddResult(added: 0, refused: 0) }
    /// Island-space cursor location during a drag (for the tile highlight); nil when the drag leaves or ends.
    var onDragLocation: (CGPoint?) -> Void = { _ in }
    private var trackingArea: NSTrackingArea?
    /// True from an accepted `draggingEntered` until `draggingEnded`; an ignored (own) drag never sets it.
    private(set) var acceptedSession = false
    private var dropped = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

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
        // NSMouseInRect includes the top edge (screen top), matching the tracking area; CGRect.contains does not.
        onPointer(NSMouseInRect(p, hotRect, isFlipped))
    }

    override func mouseEntered(with event: NSEvent) { onPointer(true) }
    override func mouseExited(with event: NSEvent) { onPointer(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }

    // MARK: Drag destination (AppKit, never SwiftUI .onDrop; the app is never activated)

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        // `draggingSource` is non-nil only for a drag started inside this app (a shelf chip).
        let op = handleEntered(pasteboard: sender.draggingPasteboard, fromThisApp: sender.draggingSource != nil)
        if op != [] { onDragLocation(islandPoint(fromWindowPoint: sender.draggingLocation)) }
        return op
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        handleUpdated(viewPoint: convert(sender.draggingLocation, from: nil))
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { handleExited() }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        handlePerform(pasteboard: sender.draggingPasteboard)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) { handleEnded() }

    private func islandPoint(fromWindowPoint p: CGPoint) -> CGPoint {
        ShelfLayout.islandPoint(fromPanelPoint: convert(p, from: nil), panelSize: bounds.size, flipped: isFlipped)
    }

    // Seams: the NSDraggingInfo overrides above only unpack the session.

    func handleEntered(pasteboard: NSPasteboard, fromThisApp: Bool = false) -> NSDragOperation {
        // Own chip drag or nothing droppable: refuse, send nothing, and ignore the rest of this session.
        // A refusal also clears any state a previous session left behind (its draggingEnded may never have arrived).
        guard !fromThisApp, !OwnDrag.active, !DroppedEntryReader.entries(from: pasteboard).isEmpty else {
            acceptedSession = false
            dropped = false
            return []
        }
        dropped = false
        acceptedSession = true
        onDragEvent(.entered)
        return .copy
    }

    func handleUpdated(viewPoint: CGPoint) -> NSDragOperation {
        guard acceptedSession else { return [] }
        onDragLocation(ShelfLayout.islandPoint(fromPanelPoint: viewPoint, panelSize: bounds.size, flipped: isFlipped))
        return .copy
    }

    func handleExited() {
        guard acceptedSession else { return }
        onDragLocation(nil)
        onDragEvent(.exited)
    }

    func handlePerform(pasteboard: NSPasteboard) -> Bool {
        guard acceptedSession else { return false }
        let result = onDrop(DroppedEntryReader.entries(from: pasteboard))
        dropped = true
        onDragLocation(nil)
        return result.added > 0 || result.refused > 0
    }

    func handleEnded() {
        guard acceptedSession else { return }
        let wasDropped = dropped
        acceptedSession = false
        dropped = false
        onDragLocation(nil)
        onDragEvent(.ended(dropped: wasDropped))
    }
}
