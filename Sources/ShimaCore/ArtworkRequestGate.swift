import Foundation

/// Track-scoped retry policy and generation tags for asynchronous artwork results.
public struct ArtworkRequestGate: Sendable {
    public struct Ticket: Equatable, Sendable {
        public let generation: UInt64
        public let trackID: String?
        public let url: URL
    }

    public enum Selection: Equatable, Sendable {
        case unchanged, clear, load(Ticket)
    }

    private var generation: UInt64 = 0
    private var trackID: String?
    private var url: URL?
    private var initialized = false
    private var failedCurrentTrack = false

    public init() {}

    public static func allows(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host?.isEmpty ?? true)
    }

    public mutating func select(trackID: String?, url: URL?) -> Selection {
        let url = url.flatMap { Self.allows($0) ? $0 : nil }
        guard !initialized || self.trackID != trackID || self.url != url else { return .unchanged }
        if self.trackID != trackID { failedCurrentTrack = false }
        initialized = true
        generation &+= 1
        self.trackID = trackID
        self.url = url
        guard let url, !failedCurrentTrack else { return .clear }
        return .load(Ticket(generation: generation, trackID: trackID, url: url))
    }

    public func accepts(_ ticket: Ticket) -> Bool {
        initialized && ticket.generation == generation && ticket.trackID == trackID && ticket.url == url
    }

    public mutating func failed(_ ticket: Ticket) {
        if accepts(ticket) { failedCurrentTrack = true }
    }
}
