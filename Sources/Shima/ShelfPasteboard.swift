import AppKit
import ShimaCore

/// What a shelf chip puts on the pasteboard when dragged out. Copy semantics: the shelf keeps the item.
/// File -> file URL (so Finder and browsers treat it as a file); text -> plain string; link -> URL plus string.
enum ShelfPasteboard {
    static func pasteboardWriter(for item: ShelfItem) -> NSPasteboardWriting {
        switch item.kind {
        case .file(let url): return url as NSURL
        case .text(let text): return text as NSString
        case .link(let url): return LinkWriter(url: url)
        }
    }

    static func write(_ item: ShelfItem, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.writeObjects([pasteboardWriter(for: item)])
    }

    /// False only for a file item whose path no longer exists.
    static func isAvailable(_ item: ShelfItem) -> Bool {
        guard case .file(let url) = item.kind else { return true }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// One pasteboard item carrying both the URL and its string form.
    private final class LinkWriter: NSObject, NSPasteboardWriting {
        let url: URL
        init(url: URL) { self.url = url }

        func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] { [.URL, .string] }

        func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
            switch type {
            case .URL: return url.absoluteString
            case .string: return url.absoluteString
            default: return nil
            }
        }
    }
}
