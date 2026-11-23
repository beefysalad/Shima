import Foundation

public enum ShelfItemKind: Equatable, Sendable {
    case file(URL)
    case text(String)
    case link(URL)
}

public struct ShelfItem: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ShelfItemKind
    public let name: String
    public let added: Date

    public init(id: UUID = UUID(), kind: ShelfItemKind, added: Date = Date()) {
        self.id = id
        self.kind = kind
        self.added = added
        let candidate: String
        let fallback: String
        switch kind {
        case .file(let url):
            candidate = url.lastPathComponent
            fallback = "File"
        case .link(let url):
            candidate = (url.host ?? "") + url.path
            fallback = url.absoluteString
        case .text(let text):
            candidate = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix { !$0.isNewline })
                .trimmingCharacters(in: .whitespaces)
            fallback = "Text"
        }
        let displayName = candidate.isEmpty ? fallback : candidate
        self.name = displayName.count > 60 ? String(displayName.prefix(59)) + "…" : displayName
    }
}
