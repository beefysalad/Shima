import Foundation
import Observation

public struct ShelfAddResult: Equatable, Sendable {
    public let added: Int
    public let refused: Int

    public init(added: Int, refused: Int) {
        self.added = added
        self.refused = refused
    }
}

@MainActor @Observable public final class ShelfStore {
    public static let cap = 20
    public private(set) var items: [ShelfItem] = []
    public var isFull: Bool { items.count >= Self.cap }

    public init() {}

    @discardableResult
    public func add(_ entries: [DroppedEntry], now: Date = Date(), makeID: () -> UUID = UUID.init) -> ShelfAddResult {
        var added = 0
        var refused = 0
        // Duplicates are decided on the standardized path, so a trailing slash or `..` segment does not defeat them.
        var seenFiles = Set(items.compactMap { item -> String? in
            guard case .file(let url) = item.kind else { return nil }
            return url.standardizedFileURL.path
        })
        for entry in entries {
            guard let kind = ShelfClassifier.classify(entry) else { continue }
            if case .file(let url) = kind,
               !seenFiles.insert(url.standardizedFileURL.path).inserted {
                continue
            }
            guard !isFull else {
                refused += 1
                continue
            }
            items.append(ShelfItem(id: makeID(), kind: kind, added: now))
            added += 1
        }
        return ShelfAddResult(added: added, refused: refused)
    }

    public func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    public func clear() {
        items.removeAll()
    }
}
