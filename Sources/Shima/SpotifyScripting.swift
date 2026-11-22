import Foundation
import ShimaCore

/// Runs Spotify Apple Events on a private serial queue, addressed by pid (never launches Spotify).
/// All work is confined to `queue`; the type holds no mutable state.
final class SpotifyScripting: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.shima.spotify-scripting", qos: .userInitiated)

    /// Reads state, position and (unless stopped) the current track, one property per event (Spike 2).
    /// The date passed to `completion` is taken right after the position reply.
    func snapshot(pid: pid_t, completion: @escaping @Sendable (Result<SpotifyReading, SpotifyScriptError>, Date) -> Void) {
        queue.async {
            do {
                let (reading, date) = try self.readSnapshot(pid: pid)
                completion(.success(reading), date)
            } catch {
                completion(.failure(Self.map(error)), Date())
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

    private func readSnapshot(pid: pid_t) throws -> (SpotifyReading, Date) {
        dispatchPrecondition(condition: .onQueue(queue))
        let state = try playbackState(pid: pid)
        let position = try SpotifyAppleEvents.get(SpotifyAppleEvents.property("pPos"), pid: pid).doubleValue
        let date = Date()
        if state == .stopped { return (SpotifyReading(state: .stopped), date) }

        let track = SpotifyAppleEvents.property("pTrk")
        func text(_ code: String) throws -> String? {
            try SpotifyAppleEvents.get(SpotifyAppleEvents.property(code, of: track), pid: pid).stringValue
        }
        let title = try text("pnam")
        let artist = try text("pArt")
        let album = try text("pAlb")
        let durationMs = try SpotifyAppleEvents.get(SpotifyAppleEvents.property("pDur", of: track), pid: pid).int32Value
        let artwork = try text("aUrl")
        let trackID = try text("ID  ")
        let reading = SpotifyReading(
            state: state, trackID: trackID, title: title, artist: artist, album: album,
            duration: TimeInterval(durationMs) / 1000, position: position,
            artworkURL: SpotifyReading.artworkURL(from: artwork))
        return (reading, date)
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
