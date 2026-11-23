import Foundation

/// Every user-facing string of the shelf and Home tab.
public enum ShelfText {
    public static let emptyState = "Drop files, text or links here"
    public static let veilCaption = "Drop to add to shelf"
    public static let veilCaptionFull = "Shelf full (20)"
    public static let clear = "Clear"
    public static let remove = "Remove"
    public static let cleared = "Shelf cleared"
    public static let homeDotTooltip = "Shelf has items"

    public static func veilCount(_ n: Int) -> String { "\(n) of 20" }

    public static func homeCount(_ n: Int) -> String {
        n == 0 ? "No items" : n == 1 ? "1 item" : "\(n) items"
    }

    public static func added(added: Int, refused: Int) -> String {
        refused > 0 ? "Added \(added), \(refused) did not fit" : "Added \(added)"
    }

    /// Chip sub-line size, as in the mockup's `fmtSize`.
    public static func fileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.\(bytes < 10240 ? 1 : 0)f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    /// File-type badge: the lower-cased extension (at most 4 characters), "file" without one, "text", "link".
    public static func badge(_ item: ShelfItem) -> String {
        switch item.kind {
        case .link: return "link"
        case .text: return "text"
        case .file(let url):
            let ext = url.pathExtension.lowercased()
            return ext.isEmpty ? "file" : String(ext.prefix(4))
        }
    }

    /// Chip sub-line: size for files, "Text" for text, the host for links.
    public static func subline(_ item: ShelfItem, fileSize bytes: Int?) -> String {
        switch item.kind {
        case .link(let url): return url.host ?? "Link"
        case .text: return "Text"
        case .file: return fileSize(bytes ?? 0)
        }
    }
}
