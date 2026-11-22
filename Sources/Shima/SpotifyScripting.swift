import Foundation
import ShimaCore

/// Runs Spotify Apple Events on a private serial queue, addressed by pid (never launches Spotify).
/// All work is confined to `queue`; the type holds no mutable state.
final class SpotifyScripting: @unchecked Sendable {
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
                try self.send(command, pid: pid)
                completion(.success(()))
            } catch {
                completion(.failure(Self.map(error)))
            }
        }
    }

    private func readSnapshot(pid: pid_t) throws -> (SpotifyReading, Date, Bool) {
        dispatchPrecondition(condition: .onQueue(queue))
        let state = try playbackState(pid: pid)
        let position = try SpotifyAppleEvents.get(SpotifyAppleEvents.property("pPos"), pid: pid).doubleValue
        let date = Date()
        if state == .stopped { return (SpotifyReading(state: .stopped), date, true) }

        let track = SpotifyAppleEvents.property("pTrk")
        func text(_ code: String) throws -> String? {
            try SpotifyAppleEvents.get(SpotifyAppleEvents.property(code, of: track), pid: pid).stringValue
        }
        let firstID = try text("ID  ")
        let title = try text("pnam")
        let artist = try text("pArt")
        let album = try text("pAlb")
        let durationMs = try SpotifyAppleEvents.get(SpotifyAppleEvents.property("pDur", of: track), pid: pid).int32Value
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
        let reply = try SpotifyAppleEvents.get(SpotifyAppleEvents.property("pPlS"), pid: pid)
        switch reply.enumCodeValue {
        case SpotifyAppleEvents.code("kPSP"): return .playing
        case SpotifyAppleEvents.code("kPSp"): return .paused
        case SpotifyAppleEvents.code("kPSS"): return .stopped
        default: throw NSError(domain: NSOSStatusErrorDomain, code: -10000)
        }
    }

    private func send(_ command: SpotifyCommand, pid: pid_t) throws {
        dispatchPrecondition(condition: .onQueue(queue))
        let id: String
        switch command {
        case .previous: id = "Prev"
        case .playPause: id = "PlPs"
        case .next: id = "Next"
        }
        try SpotifyAppleEvents.command(eventClass: "spfy", id: id, pid: pid)
    }

    private static func map(_ error: Error) -> SpotifyScriptError {
        SpotifyScriptError(code: (error as NSError).code)
    }
}
