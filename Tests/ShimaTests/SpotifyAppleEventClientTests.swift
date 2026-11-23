import Foundation
import Testing
import ShimaCore
@testable import Shima

private final class FakeScripting: SpotifyScriptingClient, @unchecked Sendable {
    typealias Snapshot = @Sendable (Result<SpotifyReading, SpotifyScriptError>, Date, Bool) -> Void
    typealias Command = @Sendable (Result<Void, SpotifyScriptError>) -> Void
    private let lock = NSLock()
    private var snapshots: [(Int32, Snapshot)] = []
    private var commands: [(SpotifyCommand, Int32, Command)] = []
    var snapshotPIDs: [Int32] { lock.withLock { snapshots.map(\.0) } }
    var sentCommands: [SpotifyCommand] { lock.withLock { commands.map(\.0) } }
    func snapshot(pid: Int32, completion: @escaping Snapshot) { lock.withLock { snapshots.append((pid, completion)) } }
    func command(_ command: SpotifyCommand, pid: Int32, completion: @escaping Command) {
        lock.withLock { commands.append((command, pid, completion)) }
    }
    func finishSnapshot(_ index: Int, _ result: Result<SpotifyReading, SpotifyScriptError>, consistent: Bool = true) {
        let callback = lock.withLock { snapshots[index].1 }
        callback(result, Date(timeIntervalSinceReferenceDate: 123), consistent)
    }
    func finishCommand(_ index: Int, _ result: Result<Void, SpotifyScriptError>) {
        let callback = lock.withLock { commands[index].2 }
        callback(result)
    }
}

@MainActor private final class SpotifyHarness {
    let scripting = FakeScripting()
    var pid: Int32? = 42
    var pidReads = 0
    var events: [SpotifyEvent] = []
    lazy var client = SpotifyAppleEventClient(scripting: scripting, pidProvider: { [weak self] in
        guard let self else { return nil }
        self.pidReads += 1
        return self.pid
    })
    init() { client.onEvent = { [weak self] in self?.events.append($0) } }
    func waitForFinish(after reads: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while pidReads <= reads && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        try #require(pidReads > reads, "Completion did not consult the fake process provider")
    }
}

@MainActor struct SpotifyAppleEventClientTests {
    private let reading = SpotifyReading(state: .playing, trackID: "fake")

    @Test func absentProcessDoesNotRequestOrCommand() {
        let h = SpotifyHarness(); h.pid = nil
        h.client.refresh(); h.client.send(.next)
        #expect(h.scripting.snapshotPIDs.isEmpty && h.scripting.sentCommands.isEmpty)
        #expect(h.events.isEmpty)
    }

    @Test func refreshesCoalesceAndDeliverScriptReadingsWithDate() async throws {
        let h = SpotifyHarness()
        h.client.refresh(); h.client.refresh(); h.client.refresh()
        #expect(h.scripting.snapshotPIDs == [42])
        var reads = h.pidReads
        h.scripting.finishSnapshot(0, .success(reading))
        try await h.waitForFinish(after: reads)
        #expect(h.scripting.snapshotPIDs == [42, 42])
        #expect(h.events == [.reading(reading, source: .script, at: Date(timeIntervalSinceReferenceDate: 123))])
        reads = h.pidReads
        h.scripting.finishSnapshot(1, .success(reading))
        try await h.waitForFinish(after: reads)
        #expect(h.events.count == 2 && h.scripting.snapshotPIDs.count == 2)
    }

    @Test(arguments: [SpotifyScriptError.permissionDenied, .timeout, .notRunning(code: -600), .other(code: 4)])
    func snapshotErrorsUsePermissionOrRefreshFailure(error: SpotifyScriptError) async throws {
        let h = SpotifyHarness(); h.client.refresh()
        let reads = h.pidReads
        h.scripting.finishSnapshot(0, .failure(error))
        try await h.waitForFinish(after: reads)
        #expect(h.events == [error == .permissionDenied ? .permissionDenied : .refreshFailed])
    }

    @Test func invalidationDropsSnapshotAndCommandAndClearsFollowUp() async throws {
        let h = SpotifyHarness()
        h.client.refresh(); h.client.refresh(); h.client.send(.next); h.client.invalidate()
        var reads = h.pidReads
        h.scripting.finishSnapshot(0, .success(reading))
        try await h.waitForFinish(after: reads)
        reads = h.pidReads
        h.scripting.finishCommand(0, .failure(.permissionDenied))
        try await h.waitForFinish(after: reads)
        #expect(h.events.isEmpty && h.scripting.snapshotPIDs.count == 1)
    }

    @Test func changedOrAbsentPIDRejectsOldCompletions() async throws {
        for pid: Int32? in [99, nil] {
            let h = SpotifyHarness(); h.client.refresh(); h.client.send(.next)
            h.pid = pid
            var reads = h.pidReads
            h.scripting.finishSnapshot(0, .success(reading))
            try await h.waitForFinish(after: reads)
            reads = h.pidReads
            h.scripting.finishCommand(0, .success(()))
            try await h.waitForFinish(after: reads)
            #expect(h.events.isEmpty)
        }
    }

    @Test func inconsistentReadIsRetriedOnceThenReportsFailure() async throws {
        let h = SpotifyHarness(); h.client.refresh()
        var reads = h.pidReads
        h.scripting.finishSnapshot(0, .success(reading), consistent: false)
        try await h.waitForFinish(after: reads)
        #expect(h.events.isEmpty && h.scripting.snapshotPIDs.count == 2)
        reads = h.pidReads
        h.scripting.finishSnapshot(1, .success(reading), consistent: false)
        try await h.waitForFinish(after: reads)
        #expect(h.events == [.refreshFailed] && h.scripting.snapshotPIDs.count == 2)
    }

    @Test func commandsDeliverOnlySuccessOrPermissionEventsWithoutSnapshot() async throws {
        let h = SpotifyHarness()
        for command in [SpotifyCommand.previous, .playPause, .next] { h.client.send(command) }
        #expect(h.scripting.sentCommands == [.previous, .playPause, .next])
        for (index, result) in [Result<Void, SpotifyScriptError>.success(()), .failure(.permissionDenied), .failure(.timeout)].enumerated() {
            let reads = h.pidReads
            h.scripting.finishCommand(index, result)
            try await h.waitForFinish(after: reads)
        }
        #expect(h.events == [.commandSucceeded(.previous), .permissionDenied])
        #expect(h.scripting.snapshotPIDs.isEmpty)
    }
}
