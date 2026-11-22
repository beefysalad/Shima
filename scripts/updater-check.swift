import AppKit
import SwiftUI
import ShimaCore
import CryptoKit

@MainActor final class UpdateCheckLogin: LoginItemService {
    var status: LoginItemStatus { .notRegistered }
    func perform(_ action: LoginItemAction) -> Bool { true }
}

@main struct UpdaterCheck {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        for name in ["ShimaBrand", "ShimaMark", "SpotifyWhite", "SpotifyGreen"] {
            precondition(BrandAssets.image(name).size.width > 0)
        }
        let shippedShima = try Data(contentsOf: URL(fileURLWithPath: "Sources/Shima/Resources/ShimaBrand.png"))
        let canonicalShima = try Data(contentsOf: URL(fileURLWithPath: "assets/branding/shima-icon-512.png"))
        precondition(shippedShima == canonicalShima)
        if CommandLine.arguments.contains("--live-check") {
            let live = AppUpdater()
            live.check()
            while live.busy { try await Task.sleep(for: .milliseconds(20)) }
            precondition(live.release != nil, live.message)
            print("Live GitHub release check PASS")
        }
        guard let fixtureVersion = Bundle(url: URL(fileURLWithPath: "dist/Shima.app"))?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            fatalError("Run scripts/package.sh --release first")
        }
        let zipURL = URL(fileURLWithPath: "dist/Shima-\(fixtureVersion).zip")
        let zip = try Data(contentsOf: zipURL)
        let sum = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
        let manifest = Data("\(sum)  Shima-\(fixtureVersion).zip\n".utf8)
        let fixture = """
        {"tag_name":"v\(fixtureVersion)","draft":false,"prerelease":false,"assets":[
        {"name":"Shima-\(fixtureVersion).zip","size":\(zip.count),"browser_download_url":"https://github.com/beefysalad/Shima/releases/download/v\(fixtureVersion)/Shima-\(fixtureVersion).zip"},
        {"name":"SHA256SUMS","size":\(manifest.count),"browser_download_url":"https://github.com/beefysalad/Shima/releases/download/v\(fixtureVersion)/SHA256SUMS"}]}
        """
        let release = try JSONDecoder().decode(AppRelease.self, from: Data(fixture.utf8))
        let folder = URL(fileURLWithPath: ".build/updater-regression", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("Shima.app")
        let stage = try await AppUpdater.prepare(release, target: target) { asset, _ in
            asset.name == "SHA256SUMS" ? manifest : zip
        }
        precondition(FileManager.default.isExecutableFile(atPath: stage.appendingPathComponent("Shima.app/Contents/MacOS/ShimaUpdater").path))
        try FileManager.default.removeItem(at: stage)
        for launchFails in [false, true] {
            let fm = FileManager.default
            let installFolder = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: installFolder, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: installFolder) }
            let installed = installFolder.appendingPathComponent("Shima.app")
            let staged = try await AppUpdater.prepare(release, target: installed) { asset, _ in
                asset.name == "SHA256SUMS" ? manifest : zip
            }
            try fm.copyItem(at: staged.appendingPathComponent("Shima.app"), to: installed)
            try Data("previous".utf8).write(to: installed.appendingPathComponent("previous-marker"))
            let helper = Process()
            helper.executableURL = folder.appendingPathComponent("helper-test")
            helper.arguments = ["99999999", installed.path, staged.path]
            var environment = ProcessInfo.processInfo.environment
            environment["SHIMA_UPDATE_TEST_TARGET"] = installed.path
            environment["SHIMA_UPDATE_TEST_OPEN_FAIL"] = launchFails ? "1" : "0"
            helper.environment = environment
            try helper.run()
            helper.waitUntilExit()
            precondition(helper.terminationStatus == (launchFails ? 1 : 0))
            precondition(fm.fileExists(atPath: installed.appendingPathComponent("previous-marker").path) == launchFails)
            if !launchFails { precondition(fm.fileExists(atPath: staged.appendingPathComponent("Previous.app/previous-marker").path)) }
            print("Installer helper \(launchFails ? "launch-failure rollback" : "successful replacement") PASS")
        }
        do {
            _ = try await AppUpdater.prepare(release, target: target) { asset, _ in
                asset.name == "SHA256SUMS" ? Data("wrong".utf8) : zip
            }
            fatalError("A tampered manifest was accepted")
        } catch { precondition(error.localizedDescription.contains("checksum")) }
        print("Archive verification and tampered download rejection PASS")

        let appState = AppState()
        let model = SettingsModel(state: appState, store: SettingsStore(storage: InMemoryPreferenceStorage()),
                                  loginItems: UpdateCheckLogin(), versionText: "Version \(fixtureVersion) (1)", readSigning: { .adHoc })
        model.refresh()
        for scenario in ["idle", "available", "signed", "current", "offline", "source", "denied"] {
            appState.spotifyAvailability = scenario == "denied" ? .permissionDenied : .notRunning
            let updater = AppUpdater(currentVersion: scenario == "current" ? fixtureVersion : "0.0.0",
                bundleURL: URL(fileURLWithPath: scenario == "source" ? "/tmp/Shima.app" : "/Applications/Shima.app"),
                signing: { scenario == "signed" ? .certificate(commonName: "Test", notAfter: nil) : .adHoc },
                loadRelease: { if scenario == "offline" { throw failure("Offline. Try again later.") }; return release })
            if scenario != "idle" {
                updater.check()
                while updater.busy { try await Task.sleep(for: .milliseconds(10)) }
            }
            switch scenario {
            case "available": precondition(updater.canInstall)
            case "signed": precondition(!updater.canInstall && updater.message.contains("signed installer"))
            case "current": precondition(!updater.canInstall && updater.message.contains("up to date"))
            case "offline": precondition(!updater.canInstall && updater.message.contains("Offline"))
            case "source": precondition(!updater.canInstall && updater.message.contains("Applications"))
            default: break
            }
            let pages: [SettingsPage] = scenario == "idle" ? SettingsPage.allCases : (scenario == "denied" ? [.music] : [.updates])
            for selectedPage in pages {
                for dark in [false, true] {
                    let host = NSHostingView(rootView: SettingsView(model: model, updater: updater, initialPage: selectedPage, onToggleLogin: {}, onEqualizerMode: { _ in }, onSpotifyRow: { _ in }).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, dark ? .dark : .light))
                    let window = NSWindow(contentRect: CGRect(origin: .zero, size: SettingsLayout.size), styleMask: .borderless, backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(100))
                    host.displayIfNeeded()
                    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("\(scenario)-\(selectedPage.rawValue)-\(dark ? "dark" : "light").png"))
                    precondition(!window.isVisible)
                    window.close()
                }
            }
            print("Settings \(scenario): \(updater.message) PASS")
        }
    }
}
