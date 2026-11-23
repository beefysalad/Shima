import AppKit
import ShimaCore
import Security

@main struct ShimaUpdater {
    @MainActor static func main() {
        let args = CommandLine.arguments
        #if UPDATER_TESTING
        let expectedTarget = ProcessInfo.processInfo.environment["SHIMA_UPDATE_TEST_TARGET"] ?? ""
        #else
        let expectedTarget = "/Applications/Shima.app"
        #endif
        guard args.count == 4,
              let invocation = UpdateInvocation.parse(arguments: args,
                  resolvedStage: { URL(fileURLWithPath: args[3]).resolvingSymlinksInPath() },
                  expectedTarget: expectedTarget) else { return }
        let pid = invocation.parentPID, target = invocation.target, stage = invocation.stage
        let fm = FileManager.default
        let backup = stage.appendingPathComponent("Previous.app")
        let incoming = stage.appendingPathComponent("Shima.app")
        do {
            // The helper also enforces this rule, even if invoked without the GUI.
            var code: SecStaticCode?, info: CFDictionary?
            guard SecStaticCodeCreateWithPath(target as CFURL, [], &code) == errSecSuccess, let code,
                  SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                  let dict = info as? [String: Any], dict[kSecCodeInfoCertificates as String] == nil else {
                throw problem("Your installed app has a certificate signature. Use the same signed installer to preserve its permissions.")
            }
            guard Bundle(url: incoming)?.bundleIdentifier == "local.shima" else { throw problem("The update is not a Shima app.") }
            try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", incoming.path])
            // Wait for the parent to exit before replacing any files. A cancelled quit leaves the app alone.
            for _ in 0..<150 {
                if kill(pid, 0) != 0 { break }
                Thread.sleep(forTimeInterval: 0.2)
            }
            guard kill(pid, 0) != 0 else { throw problem("Shima did not quit. No files were replaced; try again.") }
            try UpdateSwap.install(staged: incoming, target: target, backup: backup)
            do { try command("/usr/bin/open", ["-n", target.path]) }
            catch {
                try fm.moveItem(at: target, to: incoming)
                try fm.moveItem(at: backup, to: target)
                try? command("/usr/bin/open", ["-n", target.path])
                throw problem("The new app could not be opened. Your previous Shima has been restored.")
            }
            // Keep Previous.app for manual recovery. No other updater directories are ever deleted here.
            try? fm.removeItem(at: stage.appendingPathComponent("update.zip"))
        } catch {
            #if UPDATER_TESTING
            print(error.localizedDescription)
            exit(1)
            #else
            NSApplication.shared.setActivationPolicy(.accessory)
            let alert = NSAlert()
            alert.messageText = "Shima update couldn’t finish"
            alert.informativeText = error.localizedDescription + "\nUpdate files: " + stage.path
            alert.addButton(withTitle: "OK")
            NSApp.activate()
            alert.runModal()
            #endif
        }
    }

    static func problem(_ message: String) -> NSError { NSError(domain: "ShimaUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    static func command(_ executable: String, _ arguments: [String]) throws {
        #if UPDATER_TESTING
        if executable == "/usr/bin/open" {
            if ProcessInfo.processInfo.environment["SHIMA_UPDATE_TEST_OPEN_FAIL"] == "1" { throw problem("Simulated launch failure") }
            return
        }
        #endif
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw problem("Could not complete \(URL(fileURLWithPath: executable).lastPathComponent).") }
    }
}
