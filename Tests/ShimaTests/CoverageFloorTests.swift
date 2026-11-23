import Foundation
import Testing

struct CoverageFloorTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func file(_ module: String, covered: Any, count: Any = 100) -> [String: Any] {
        ["filename": repository.appendingPathComponent("Sources/\(module)/Fixture.swift").path,
         "summary": ["lines": ["covered": covered, "count": count, "percent": 100]]]
    }

    private func report(core: Any = 90, app: Any = 50) -> [String: Any] {
        ["data": [["files": [file("ShimaCore", covered: core), file("Shima", covered: app),
                              file("ShimaUpdater", covered: 50), file("shimactl", covered: 50)],
                   "totals": ["lines": ["covered": 1_000_000, "count": 1_000_000, "percent": 100]]]]]
    }

    private func run(_ payload: [String: Any]) async throws -> (status: Int32, output: String) {
        let folder = repository.appendingPathComponent(".build/coverage-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("report.json")
        try JSONSerialization.data(withJSONObject: payload).write(to: path)
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-I", repository.appendingPathComponent("scripts/coverage.py").path,
                             "--report", path.path, "--core-floor", "90", "--overall-floor", "60"]
        process.currentDirectoryURL = repository
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let deadline = ContinuousClock.now + .seconds(5)
        while process.isRunning, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        let timedOut = process.isRunning
        if timedOut { process.terminate() }
        try #require(!timedOut, "Coverage report validation must finish promptly")
        return (process.terminationStatus, String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    @Test func acceptsCoverageAtBothFloorsUsingCountsRatherThanReportedPercent() async throws {
        let result = try await run(report())
        #expect(result.status == 0, "\(result.output)")
        #expect(result.output.contains("ShimaCore: 90.00% (90/100)"))
        #expect(result.output.contains("Overall production: 60.00% (240/400)"))
    }

    @Test func rejectsCoreBelowItsFloor() async throws {
        let result = try await run(report(core: 89))
        #expect(result.status == 1)
        #expect(result.output.contains("ShimaCore is below"))
    }

    @Test func rejectsOverallCoverageBelowItsFloor() async throws {
        let result = try await run(report(app: 49))
        #expect(result.status == 1)
        #expect(result.output.contains("Overall production is below"))
    }

    @Test func excludesTestsAndExternalSourcesEvenWhenTheyInflateTotals() async throws {
        var payload = report(app: 49)
        var data = payload["data"] as! [[String: Any]]
        var files = data[0]["files"] as! [[String: Any]]
        files.append(["filename": repository.appendingPathComponent("Tests/ShimaTests/Fixture.swift").path,
                      "summary": ["lines": ["covered": 1_000_000, "count": 1_000_000]]])
        files.append(["filename": "/external/Sources/Shima/Fixture.swift",
                      "summary": ["lines": ["covered": 1_000_000, "count": 1_000_000]]])
        data[0]["files"] = files
        payload["data"] = data
        let result = try await run(payload)
        #expect(result.status == 1)
        #expect(result.output.contains("Overall production: 59.75% (239/400)"))
    }

    @Test func rejectsReportsMissingAnExecutableModule() async throws {
        var payload = report()
        var data = payload["data"] as! [[String: Any]]
        data[0]["files"] = (data[0]["files"] as! [[String: Any]]).dropLast().map { $0 }
        payload["data"] = data
        let result = try await run(payload)
        #expect(result.status == 2)
        #expect(result.output.contains("Missing production coverage: shimactl"))
    }

    @Test func rejectsExecutableModulesWithNoInstrumentedLines() async throws {
        var payload = report()
        var data = payload["data"] as! [[String: Any]]
        var files = data[0]["files"] as! [[String: Any]]
        files[3] = file("shimactl", covered: 0, count: 0)
        data[0]["files"] = files
        payload["data"] = data
        let result = try await run(payload)
        #expect(result.status == 2)
        #expect(result.output.contains("Empty production coverage: shimactl"))
    }

    @Test func normalizesPathsBeforeExcludingTestSourceInflation() async throws {
        var payload = report(app: 49)
        var data = payload["data"] as! [[String: Any]]
        var files = data[0]["files"] as! [[String: Any]]
        files.append(["filename": repository.path + "/Sources/Shima/../../Tests/ShimaTests/Fixture.swift",
                      "summary": ["lines": ["covered": 1_000_000, "count": 1_000_000]]])
        data[0]["files"] = files
        payload["data"] = data
        let result = try await run(payload)
        #expect(result.status == 1)
        #expect(result.output.contains("Overall production: 59.75% (239/400)"))
    }

    @Test func rejectsMalformedAndImpossibleLineCounts() async throws {
        for payload in [report(core: 101), report(core: -1), report(core: "90"), ["data": []]] {
            let result = try await run(payload)
            #expect(result.status == 2)
            #expect(result.output.contains("Invalid coverage report"))
        }
    }
}
