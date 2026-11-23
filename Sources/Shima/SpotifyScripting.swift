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

final class SpotifyScripting: @unchecked Sendable {
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
                let (reading, date, consistent) = try self.readSnapshot(pid: pid)
                completion(.success(reading), date, consistent)
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

    private func readSnapshot(pid: pid_t) throws -> (SpotifyReading, Date, Bool) {
        dispatchPrecondition(condition: .onQueue(queue))
        let state = try playbackState(pid: pid)
        let position = try transport.get("pPos", track: false, pid: pid).doubleValue
        let date = now()
        if state == .stopped { return (SpotifyReading(state: .stopped), date, true) }

        func text(_ code: String) throws -> String? {
            try transport.get(code, track: true, pid: pid).stringValue
        }
        let firstID = try text("ID  ")
        let title = try text("pnam")
        let artist = try text("pArt")
        let album = try text("pAlb")
        let durationMs = try transport.get("pDur", track: true, pid: pid).int32Value
        let artwork = try text("aUrl")
        let trackID = try text("ID  ")
        let consistent = SpotifySnapshotConsistency.isConsistent(firstTrackID: firstID, lastTrackID: trackID)
        let reading = SpotifyReading(
            state: state, trackID: trackID, title: title, artist: artist, album: album,
            duration: TimeInterval(durationMs) / 1000, position: position,
            artworkURL: SpotifyReading.artworkURL(from: artwork))
        return (reading, date, consistent)
    }

    private func playbackState(pid: pid_t) throws -> PlaybackState {
        dispatchPrecondition(condition: .onQueue(queue))
        let reply = try transport.get("pPlS", track: false, pid: pid)
        switch reply.enumCodeValue {
        case SpotifyAppleEvents.code("kPSP"): return .playing
        case SpotifyAppleEvents.code("kPSp"): return .paused
        case SpotifyAppleEvents.code("kPSS"): return .stopped
        default: throw NSError(domain: NSOSStatusErrorDomain, code: -10000)
        }
    }

    private static func map(_ error: Error) -> SpotifyScriptError {
        SpotifyScriptError(code: (error as NSError).code)
    }
}
