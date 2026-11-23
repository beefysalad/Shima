import Foundation

public struct DroppedEntry: Equatable, Sendable {
    public var fileURL: URL?
    public var url: URL?
    public var string: String?

    public init(fileURL: URL? = nil, url: URL? = nil, string: String? = nil) {
        self.fileURL = fileURL
        self.url = url
        self.string = string
    }
}

public enum ShelfClassifier {
    /// A dropped snippet is stored (and written back on drag-out) at most this long.
    public static let maxTextLength = 100_000

    public static func classify(_ entry: DroppedEntry) -> ShelfItemKind? {
        if let fileURL = entry.fileURL, fileURL.isFileURL {
            return .file(fileURL)
        }
        if let url = entry.url, isHTTP(url) {
            return .link(url)
        }
        guard let string = entry.string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), isHTTP(url) {
            return .link(url)
        }
        return .text(String(string.prefix(maxTextLength)))
    }

    private static func isHTTP(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}
