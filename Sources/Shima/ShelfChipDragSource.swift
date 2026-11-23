import AppKit
import SwiftUI
import ShimaCore

/// Transparent drag source laid over a shelf chip (under its x button). Starts a copy drag after a small
/// movement threshold. The panel is non-key and must never be activated, so first clicks are accepted.
struct ShelfChipDragSource: NSViewRepresentable {
    let item: ShelfItem
    let onMissing: @MainActor (UUID) -> Void
    let onDragStarted: @MainActor () -> Void

    func makeNSView(context: Context) -> ShelfChipDragView {
        let view = ShelfChipDragView(scheduler: DispatchScheduler())
        configure(view)
        return view
    }

    func updateNSView(_ view: ShelfChipDragView, context: Context) { configure(view) }

    private func configure(_ view: ShelfChipDragView) {
        view.item = item
        view.onMissing = onMissing
        view.onDragStarted = onDragStarted
    }
}

@MainActor final class ShelfChipDragView: NSView, NSDraggingSource {
    static let threshold: CGFloat = 4
    static let collapseDelay: Duration = .milliseconds(250)

    var item: ShelfItem?
    var onMissing: (@MainActor (UUID) -> Void)?
    var onDragStarted: (@MainActor () -> Void)?
    private let scheduler: any Scheduler
    private var startTask: (any ScheduledTask)?
    private var mouseDownPoint: NSPoint?

    init(scheduler: any Scheduler) {
        self.scheduler = scheduler
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = mouseDownPoint, let item else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - origin.x, p.y - origin.y) >= Self.threshold else { return }
        mouseDownPoint = nil
        guard prepareDrag() else { return }
        let dragItem = NSDraggingItem(pasteboardWriter: ShelfPasteboard.pasteboardWriter(for: item))
        dragItem.setDraggingFrame(bounds, contents: Self.dragImage(for: item, size: bounds.size))
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    /// Checks the item before a drag starts. A file that vanished is removed from the shelf instead.
    func prepareDrag() -> Bool {
        guard let item else { return false }
        guard ShelfPasteboard.isAvailable(item) else {
            Log.shelf.info("shelf drag-out skipped missing file")
            onMissing?(item.id)
            return false
        }
        return true
    }

    // MARK: NSDraggingSource

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        MainActor.assumeIsolated { sessionWillBegin() }
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        MainActor.assumeIsolated { sessionEnded(operation: operation) }
    }

    func sessionWillBegin() {
        OwnDrag.active = true
        if let item {
            let kind: String
            switch item.kind {
            case .file: kind = "file"
            case .text: kind = "text"
            case .link: kind = "link"
            }
            Log.shelf.info("shelf drag-out started kind=\(kind, privacy: .public)")
        }
        startTask?.cancel()
        startTask = scheduler.schedule(after: Self.collapseDelay) { [weak self] in
            self?.startTask = nil
            self?.onDragStarted?()
        }
    }

    func sessionEnded(operation: NSDragOperation) {
        OwnDrag.active = false
        Log.shelf.info("shelf drag-out ended operation=\(operation.rawValue, privacy: .public)")
    }

    /// A simple badge-and-name image standing in for the chip.
    private static func dragImage(for item: ShelfItem, size: NSSize) -> NSImage {
        let size = NSSize(width: max(size.width, 60), height: max(size.height, 32))
        return NSImage(size: size, flipped: false) { rect in
            NSColor(white: 0.18, alpha: 0.92).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byTruncatingTail
            let text = NSAttributedString(string: item.name, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white, .paragraphStyle: para])
            text.draw(in: NSRect(x: 8, y: rect.midY - 7, width: rect.width - 16, height: 14))
            return true
        }
    }
}
