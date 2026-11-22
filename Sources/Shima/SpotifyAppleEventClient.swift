import AppKit
import ShimaCore

/// `SpotifyClient` over Apple Events. Sends nothing without a live Spotify pid, never launches Spotify.
@MainActor
final class SpotifyAppleEventClient: SpotifyClient {
    var onEvent: (@MainActor (SpotifyEvent) -> Void)?
    private let scripting: SpotifyScripting
    private var gate = SpotifyRequestGate()

    init(scripting: SpotifyScripting = SpotifyScripting()) {
        self.scripting = scripting
    }

    static func spotifyPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
            .first { !$0.isTerminated }?.processIdentifier
    }

    func refresh() {
        guard let pid = Self.spotifyPID() else { return }
        guard let ticket = gate.request(pid: pid) else {
            Log.spotify.info("spotify refresh coalesced")
            return
        }
        run(ticket)
    }

    func send(_ command: SpotifyCommand) {
        guard let pid = Self.spotifyPID() else { return }
        let ticket = gate.ticket(pid: pid)
        scripting.command(command, pid: pid) { [weak self] result in
            Task { @MainActor in self?.commandFinished(command, ticket, result) }
        }
    }

    func invalidate() {
        gate.invalidate()
    }

    private func run(_ ticket: SpotifyRequestGate.Ticket) {
        Log.spotify.info("spotify refresh seq=\(ticket.seq, privacy: .public) pid=\(ticket.pid, privacy: .public)")
        scripting.snapshot(pid: ticket.pid) { [weak self] result, date in
            Task { @MainActor in self?.finished(ticket, result, date) }
        }
    }

    private func finished(_ ticket: SpotifyRequestGate.Ticket, _ result: Result<SpotifyReading, SpotifyScriptError>, _ date: Date) {
        let outcome = gate.finish(ticket, currentPid: Self.spotifyPID())
        var suffix = ""
        if case let .failure(error) = result { suffix = " error=\(Self.code(error))" }
        Log.spotify.info("spotify result seq=\(ticket.seq, privacy: .public) applied=\(outcome.apply, privacy: .public)\(suffix, privacy: .public)")
        if outcome.apply {
            switch result {
            case let .success(reading): onEvent?(.reading(reading, source: .script, at: date))
            case .failure(.permissionDenied): onEvent?(.permissionDenied)
            case .failure: break  // didTerminate is the authority for "not running"; a timeout waits for the next broadcast or open
            }
        }
        if let next = outcome.next { run(next) }
    }

    private func commandFinished(_ command: SpotifyCommand, _ ticket: SpotifyRequestGate.Ticket, _ result: Result<Void, SpotifyScriptError>) {
        let outcome = gate.finish(ticket, currentPid: Self.spotifyPID())
        var status = "ok"
        if case let .failure(error) = result {
            status = "error=\(Self.code(error))"
            if outcome.apply, error == .permissionDenied { onEvent?(.permissionDenied) }
        }
        let succeeded: Bool
        if case .success = result { succeeded = true } else { succeeded = false }
        Log.spotify.info("spotify command result \(command.rawValue, privacy: .public) seq=\(ticket.seq, privacy: .public) \(status, privacy: .public)")
        if succeeded, outcome.apply { onEvent?(.commandSucceeded(command)) }
    }

    private static func code(_ error: SpotifyScriptError) -> Int {
        switch error {
        case let .notRunning(code), let .other(code): return code
        case .permissionDenied: return -1743
        case .timeout: return -1712
        }
    }
}
