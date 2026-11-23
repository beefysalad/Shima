import Foundation
import Testing

/// Exercise only inputs rejected before signing, process waiting, file swapping or UI.
private final class UpdaterTestBundleMarker: NSObject {}

struct UpdaterInvocationCharacterizationTests {
    @Test func invalidProductionInvocationsExitWithoutOutput() async throws {
        let uuid = UUID().uuidString
        let cases: [[String]] = [
            [], ["2"], ["2", "/Applications/Shima.app"],
            ["invalid", "/Applications/Shima.app", "/Applications/.shima-update-\(uuid)"],
            ["1", "/Applications/Shima.app", "/Applications/.shima-update-\(uuid)"],
            ["0", "/Applications/Shima.app", "/Applications/.shima-update-\(uuid)"],
            ["2147483648", "/Applications/Shima.app", "/Applications/.shima-update-\(uuid)"],
            ["2", "/Applications/Other.app", "/Applications/.shima-update-\(uuid)"],
            ["2", "/Applications/Shima.app", "/Applications/not-a-stage"],
            ["2", "/Applications/Shima.app", "/Applications/.shima-update-invalid"],
            ["2", "/Applications/Shima.app", "/Applications/nested/.shima-update-\(uuid)"],
        ]
        // Locate SwiftPM's built helper beside the test bundle on either build layout.
        var directory = Bundle(for: UpdaterTestBundleMarker.self).bundleURL
        while directory.path != "/", !FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("ShimaUpdater").path) {
            directory.deleteLastPathComponent()
        }
        let helper = directory.appendingPathComponent("ShimaUpdater")
        try #require(FileManager.default.isExecutableFile(atPath: helper.path))
        let profileDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/updater-validation", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        for arguments in cases {
            let process = Process()
            let output = Pipe()
            process.executableURL = helper
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["LLVM_PROFILE_FILE"] = profileDirectory.appendingPathComponent("helper-%p.profraw").path
            process.environment = environment
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while process.isRunning, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            let timedOut = process.isRunning
            if timedOut { process.terminate() }
            #expect(!timedOut, "Invalid helper arguments must exit immediately: \(arguments)")
            if !timedOut {
                #expect(process.terminationStatus == 0)
                #expect(output.fileHandleForReading.readDataToEndOfFile().isEmpty)
            }
        }
    }
}
