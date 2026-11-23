import Foundation
import Testing

private final class CLITestBundleMarker: NSObject {}

struct ShimactlTests {
    @Test func stubExitsSuccessfullyForAnyArgumentsWithoutOutput() async throws {
        var directory = Bundle(for: CLITestBundleMarker.self).bundleURL
        while directory.path != "/", !FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("shimactl").path) {
            directory.deleteLastPathComponent()
        }
        let executable = directory.appendingPathComponent("shimactl")
        try #require(FileManager.default.isExecutableFile(atPath: executable.path))
        // Keep child profiles beside SwiftPM's test profiles so coverage includes the CLI.
        let profiles = directory.appendingPathComponent("codecov", isDirectory: true)
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)
        for arguments in [[], ["event", "started"], ["--unknown", "", "日本語", "spaces and punctuation !?"], Array(repeating: "arg", count: 100)] {
            let process = Process()
            let output = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["LLVM_PROFILE_FILE"] = profiles.appendingPathComponent("shimactl-%m-%p.profraw").path
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
            #expect(!timedOut, "Hook CLI must exit quickly")
            if !timedOut {
                #expect(process.terminationStatus == 0)
                #expect(output.fileHandleForReading.readDataToEndOfFile().isEmpty)
            }
        }
    }
}
