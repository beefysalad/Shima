import AppKit
import ShimaCore

/// Turns a drag pasteboard into `DroppedEntry` values: one per pasteboard item, carrying every
/// representation it offers, so `ShelfClassifier` decides precedence.
enum DroppedEntryReader {
    static func entries(from pasteboard: NSPasteboard) -> [DroppedEntry] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            let entry = DroppedEntry(
                fileURL: item.string(forType: .fileURL).flatMap { URL(string: $0) },
                url: item.string(forType: .URL).flatMap { URL(string: $0) },
                string: item.string(forType: .string))
            return entry.fileURL == nil && entry.url == nil && entry.string == nil ? nil : entry
        }
    }
}
