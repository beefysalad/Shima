/// Coalesces snapshots while keeping command tickets independent.
public struct SpotifyRequestGate: Equatable, Sendable {
    public struct Ticket: Equatable, Sendable {
        public let seq: Int
        public let pid: Int32

        public init(seq: Int, pid: Int32) {
            self.seq = seq
            self.pid = pid
        }
    }

    public struct Outcome: Equatable, Sendable {
        public let apply: Bool
        public let next: Ticket?

        public init(apply: Bool, next: Ticket?) {
            self.apply = apply
            self.next = next
        }
    }

    private var nextSeq = 1
    private var current: Ticket?
    private var dirty = false
    private var staleThrough = 0

    public init() {}

    public var inFlight: Bool { current != nil }

    /// Starts a snapshot, or marks that one follow-up is owed.
    public mutating func request(pid: Int32) -> Ticket? {
        guard current == nil else {
            dirty = true
            return nil
        }
        let next = ticket(pid: pid)
        current = next
        return next
    }

    /// Issues a command ticket without changing snapshot state.
    public mutating func ticket(pid: Int32) -> Ticket {
        let issued = Ticket(seq: nextSeq, pid: pid)
        nextSeq += 1
        return issued
    }

    /// Call when a request or command finishes on the owning actor.
    public mutating func finish(_ ticket: Ticket, currentPid: Int32?) -> Outcome {
        let apply = ticket.seq > staleThrough && ticket.pid == currentPid
        guard ticket == current else {
            return Outcome(apply: apply, next: nil)
        }

        current = nil
        let needsFollowUp = dirty
        dirty = false
        let next: Ticket?
        if needsFollowUp, let currentPid {
            next = request(pid: currentPid)
        } else {
            next = nil
        }
        return Outcome(apply: apply, next: next)
    }

    /// Stales all issued tickets and clears the follow-up owed before quit.
    /// The running snapshot remains in flight until its completion arrives.
    public mutating func invalidate() {
        staleThrough = nextSeq - 1
        dirty = false
    }
}

public enum SpotifyScriptError: Error, Equatable, Sendable {
    case notRunning(code: Int)
    case permissionDenied
    case timeout
    case other(code: Int)

    public init(code: Int) {
        switch code {
        case -600, -609: self = .notRunning(code: code)
        case -1743: self = .permissionDenied
        case -1712: self = .timeout
        default: self = .other(code: code)
        }
    }
}
