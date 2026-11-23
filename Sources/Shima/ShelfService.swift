import Foundation
import Observation
import ShimaCore

enum ShelfDragEvent: Equatable {
    case entered, exited, ended(dropped: Bool)
}

/// Owns the shelf store, the transient "Added n" status and, under `SHIMA_FAKE_SHELF=1`,
/// the distributed-notification driver. Nothing is scheduled while idle: the status clear is one
/// one-shot task per drop.
@Observable @MainActor final class ShelfService: NSObject {
    static let statusDuration: Duration = .milliseconds(2200)

    @ObservationIgnored let store = ShelfStore()
    @ObservationIgnored var onDragEvent: ((ShelfDragEvent) -> Void)?
    @ObservationIgnored var onDropped: (() -> Void)?
    private(set) var status: String?
    /// True when the status reports refused items (drawn in the warning colour).
    private(set) var statusWarn = false
    @ObservationIgnored private(set) var isObservingFake = false
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private var clearTask: (any ScheduledTask)?
    @ObservationIgnored private var pending: [DroppedEntry] = []

    init(environment: [String: String], scheduler: any Scheduler = DispatchScheduler()) {
        self.scheduler = scheduler
        super.init()
        if environment["SHIMA_FAKE_SHELF"] == "1" {
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(fakeControl(_:)), name: .init("local.shima.fake-shelf"),
                object: nil, suspensionBehavior: .deliverImmediately)
            isObservingFake = true
        }
    }

    func shutdown() {
        DistributedNotificationCenter.default().removeObserver(self)
        isObservingFake = false
        clearTask?.cancel()
        clearTask = nil
    }

    @discardableResult
    func drop(_ entries: [DroppedEntry]) -> ShelfAddResult {
        let result = store.add(entries)
        Log.shelf.info("shelf drop added=\(result.added, privacy: .public) refused=\(result.refused, privacy: .public) items=\(self.store.items.count, privacy: .public)")
        guard result.added > 0 || result.refused > 0 else { return result }
        statusWarn = result.refused > 0
        status = ShelfText.added(added: result.added, refused: result.refused)
        clearTask?.cancel()
        clearTask = scheduler.schedule(after: Self.statusDuration) { [weak self] in
            self?.status = nil
            self?.statusWarn = false
            self?.clearTask = nil
        }
        if result.added > 0 { onDropped?() }
        return result
    }

    private func emit(_ event: ShelfDragEvent) {
        Log.shelf.info("shelf drag \(String(describing: event), privacy: .public)")
        onDragEvent?(event)
    }

    @objc nonisolated private func fakeControl(_ note: Notification) {
        guard let line = note.object as? String else { return }
        MainActor.assumeIsolated { handleFake(line) }
    }

    private func handleFake(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let command = parts.first.map(String.init) else { return }
        let argument = parts.count > 1 ? String(parts[1]) : ""
        Log.shelf.info("shelf fake \(command, privacy: .public)")
        switch command {
        case "add-file" where !argument.isEmpty:
            pending.append(DroppedEntry(fileURL: URL(fileURLWithPath: argument)))
        case "add-text" where !argument.isEmpty:
            pending.append(DroppedEntry(string: argument))
        case "add-link" where !argument.isEmpty:
            pending.append(DroppedEntry(url: URL(string: argument)))
        case "drag-enter": emit(.entered)
        case "drag-exit": emit(.exited)
        case "drop":
            let entries = pending
            pending = []
            drop(entries)
            emit(.ended(dropped: true))
        case "drop-cancel":
            pending = []
            emit(.ended(dropped: false))
        case "clear":
            store.clear()
            Log.shelf.info("shelf cleared items=\(self.store.items.count, privacy: .public)")
        default: break
        }
    }
}
