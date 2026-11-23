import Foundation
import Testing
import ShimaCore
@testable import Shima

struct SpotifyScriptingTests {
    @Test func exitedPIDReportsMinus600ForSnapshotAndCommand() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit()
        let pid = child.processIdentifier
        try #require(kill(pid, 0) == -1 && errno == ESRCH)
        let scripting = SpotifyScripting()
        let snapshot = await withCheckedContinuation { continuation in
            scripting.snapshot(pid: pid) { result, _, consistent in
                #expect(consistent)
                continuation.resume(returning: result)
            }
        }
        #expect(snapshot == .failure(.notRunning(code: -600)))
        try #require(kill(pid, 0) == -1 && errno == ESRCH)
        let command: Result<Void, SpotifyScriptError> = await withCheckedContinuation { continuation in
            scripting.command(.next, pid: pid) { continuation.resume(returning: $0) }
        }
        if case let .failure(error) = command { #expect(error == .notRunning(code: -600)) }
        else { Issue.record("An exited pid accepted a command") }
    }
}

private final class ScriptFixture: @unchecked Sendable, SpotifyEventTransport {
    enum Value { case text(String?), integer(Int32), double(Double), state(String), failure(Int) }
    private let lock = NSLock()
    private var entries: [String] = []
    let values: [String: Value]
    let commandError: Int?
    init(_ values: [String: Value], commandError: Int? = nil) { self.values = values; self.commandError = commandError }
    var calls: [String] { lock.withLock { entries } }
    func record(_ value: String) { lock.withLock { entries.append(value) } }
    func get(_ property: String, track: Bool, pid: Int32) throws -> NSAppleEventDescriptor {
        record("\(pid):\(track ? "track:" : "")\(property)")
        switch values[property] ?? .text(nil) {
        case let .text(value): return value.map(NSAppleEventDescriptor.init(string:)) ?? .null()
        case let .integer(value): return NSAppleEventDescriptor(int32: value)
        case let .double(value): return NSAppleEventDescriptor(double: value)
        case let .state(value): return NSAppleEventDescriptor(enumCode: SpotifyAppleEvents.code(value))
        case let .failure(code): throw NSError(domain: NSOSStatusErrorDomain, code: code)
        }
    }
    func command(_ command: SpotifyCommand, pid: Int32) throws {
        record("\(pid):\(command.rawValue)")
        if let commandError { throw NSError(domain: NSOSStatusErrorDomain, code: commandError) }
    }
}

extension SpotifyScriptingTests {
    @Test func snapshotReadsPropertiesInOrderAndDatesThePositionReply() async throws {
        let fixture = ScriptFixture(["pPlS": .state("kPSP"), "pPos": .double(12.5), "ID  ": .text("track"),
                                     "pnam": .text("Song"), "pArt": .text("Artist"), "pAlb": .text("Album"),
                                     "pDur": .integer(123456), "aUrl": .text("https://i.scdn.co/art")])
        let date = Date(timeIntervalSinceReferenceDate: 123)
        let scripting = SpotifyScripting(transport: fixture, now: { fixture.record("date"); return date })
        let (result, actualDate, consistent) = await withCheckedContinuation { continuation in
            scripting.snapshot(pid: 17) { continuation.resume(returning: ($0, $1, $2)) }
        }
        #expect(try result.get() == SpotifyReading(state: .playing, trackID: "track", title: "Song", artist: "Artist",
                                                  album: "Album", duration: 123.456, position: 12.5,
                                                  artworkURL: URL(string: "https://i.scdn.co/art")))
        #expect(actualDate == date && consistent)
        #expect(fixture.calls == ["17:pPlS", "17:pPos", "date", "17:track:ID  ", "17:track:pnam", "17:track:pArt",
                                  "17:track:pAlb", "17:track:pDur", "17:track:aUrl", "17:track:ID  "])
    }

    @Test func stoppedSnapshotReadsPositionButSkipsTrack() async throws {
        let fixture = ScriptFixture(["pPlS": .state("kPSS"), "pPos": .double(99)])
        let scripting = SpotifyScripting(transport: fixture)
        let result = await withCheckedContinuation { continuation in
            scripting.snapshot(pid: 18) { result, _, consistent in
                #expect(consistent)
                continuation.resume(returning: result)
            }
        }
        #expect(try result.get() == SpotifyReading(state: .stopped))
        #expect(fixture.calls == ["18:pPlS", "18:pPos"])
    }

    @Test(arguments: [-600, -609, -1743, -1712, -10000])
    func snapshotAndCommandMapErrors(code: Int) async {
        let fixture = ScriptFixture(["pPlS": .failure(code)], commandError: code)
        let scripting = SpotifyScripting(transport: fixture)
        let snapshot = await withCheckedContinuation { continuation in
            scripting.snapshot(pid: 19) { result, _, _ in continuation.resume(returning: result) }
        }
        #expect(snapshot == .failure(SpotifyScriptError(code: code)))
        let command: Result<Void, SpotifyScriptError> = await withCheckedContinuation { continuation in
            scripting.command(.previous, pid: 19) { continuation.resume(returning: $0) }
        }
        if case let .failure(error) = command { #expect(error == SpotifyScriptError(code: code)) }
        else { Issue.record("Command error was lost") }
    }

    @Test func unknownPlaybackStateIsAnErrorAndDoesNotReadPosition() async {
        let fixture = ScriptFixture(["pPlS": .state("oops")])
        let scripting = SpotifyScripting(transport: fixture)
        let result = await withCheckedContinuation { continuation in
            scripting.snapshot(pid: 20) { result, _, _ in continuation.resume(returning: result) }
        }
        #expect(result == .failure(.other(code: -10000)))
        #expect(fixture.calls == ["20:pPlS"])
    }
}
