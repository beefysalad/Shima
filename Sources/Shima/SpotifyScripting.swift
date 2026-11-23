import Foundation
import ShimaCore

/// Runs Spotify Apple Events on a private serial queue, addressed by pid (never launches Spotify).
/// All work is confined to `queue`; the type holds no mutable state.
protocol SpotifyEventTransport: Sendable {
    func get(_ property: String, track: Bool, pid: Int32) throws -> NSAppleEventDescriptor
    func command(_ command: SpotifyCommand, pid: Int32) throws
}

private struct AppleEventTransport: SpotifyEventTransport {
    func get(_ property: String, track: Bool, pid: Int32) throws -> NSAppleEventDescriptor {
        let container = track ? SpotifyAppleEvents.property("pTrk") : .null()
        return try SpotifyAppleEvents.get(SpotifyAppleEvents.property(property, of: container), pid: pid)
    }

    func command(_ command: SpotifyCommand, pid: Int32) throws {
        let id: String
        switch command {
        case .previous: id = "Prev"
        case .playPause: id = "PlPs"
        case .next: id = "Next"
        }
        try SpotifyAppleEvents.command(eventClass: "spfy", id: id, pid: pid)
    }
}

protocol SpotifyScriptingClient: Sendable {
    func snapshot(pid: Int32, completion: @escaping @Sendable (Result<SpotifyReading, SpotifyScriptError>, Date, Bool) -> Void)
    func command(_ command: SpotifyCommand, pid: Int32, completion: @escaping @Sendable (Result<Void, SpotifyScriptError>) -> Void)
}

final class SpotifyScripting: SpotifyScriptingClient, @unchecked Sendable {
    private let transport: any SpotifyEventTransport
    private let now: @Sendable () -> Date

    init(transport: any SpotifyEventTransport = AppleEventTransport(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.now = now
    }
    private let queue = DispatchQueue(label: "local.shima.spotify-scripting", qos: .userInitiated)

    /// Reads state, position and (unless stopped) the current track, one property per event (Spike 2).
    /// The date passed to `completion` is taken right after the position reply.
    /// `consistent` is false when the track id read first differs from the one read last (track changed mid-snapshot).
    func snapshot(pid: pid_t, completion: @escaping @Sendable (Result<SpotifyReading, SpotifyScriptError>, Date, _ consistent: Bool) -> Void) {
        queue.async {
            do {
                dispatchPrecondition(condition: .onQueue(self.queue))
                let snapshot = try SpotifySnapshot.read(from: AppleEventSnapshotSource(transport: self.transport, pid: pid), now: self.now)
                completion(.success(snapshot.reading), snapshot.date, snapshot.consistent)
            } catch {
                completion(.failure(Self.map(error)), Date(), true)
            }
        }
    }

    func command(_ command: SpotifyCommand, pid: pid_t, completion: @escaping @Sendable (Result<Void, SpotifyScriptError>) -> Void) {
        queue.async {
            do {
                try self.transport.command(command, pid: pid)
                completion(.success(()))
            } catch {
                completion(.failure(Self.map(error)))
            }
        }
    }

    private static func map(_ error: Error) -> SpotifyScriptError {
        SpotifyScriptError(code: (error as NSError).code)
    }
}

private struct AppleEventSnapshotSource: SpotifySnapshotSource {
    let transport: any SpotifyEventTransport
    let pid: Int32

    func playbackState() throws -> PlaybackState {
        let reply = try transport.get("pPlS", track: false, pid: pid)
        switch reply.enumCodeValue {
        case SpotifyAppleEvents.code("kPSP"): return .playing
        case SpotifyAppleEvents.code("kPSp"): return .paused
        case SpotifyAppleEvents.code("kPSS"): return .stopped
        default: throw NSError(domain: NSOSStatusErrorDomain, code: -10000)
        }
    }

    func position() throws -> TimeInterval { try transport.get("pPos", track: false, pid: pid).doubleValue }
    func text(_ property: SpotifyTrackText) throws -> String? { try transport.get(property.rawValue, track: true, pid: pid).stringValue }
    func durationMilliseconds() throws -> Int32 { try transport.get("pDur", track: true, pid: pid).int32Value }
}
