import AppKit
import Observation
import ShimaCore

@Observable @MainActor
final class AppUpdater {
    private(set) var message = "Check GitHub for a new release."
    private(set) var busy = false
    private(set) var release: AppRelease?
    private(set) var canInstall = false
    private let current: String
    private let bundleURL: URL
    private let signing: @MainActor () -> SigningSummary
    private let loadRelease: (@Sendable () async throws -> AppRelease)?
    private let isWritable: @MainActor (String) -> Bool

    init(currentVersion: String? = nil, bundleURL: URL = Bundle.main.bundleURL,
         signing: @escaping @MainActor () -> SigningSummary = { SigningInfo.read() },
         loadRelease: (@Sendable () async throws -> AppRelease)? = nil,
         isWritable: @escaping @MainActor (String) -> Bool = { FileManager.default.isWritableFile(atPath: $0) }) {
        self.current = currentVersion ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        self.bundleURL = bundleURL
        self.signing = signing
        self.loadRelease = loadRelease
        self.isWritable = isWritable
    }

    func check() {
        guard !busy else { return }
        busy = true
        release = nil
        canInstall = false
        message = "Checking for updates…"
        Task {
            defer { busy = false }
            do {
                let found: AppRelease
                if let loadRelease { found = try await loadRelease() }
                else {
                    var request = URLRequest(url: URL(string: "https://api.github.com/repos/beefysalad/Shima/releases/latest")!)
                    request.timeoutInterval = 30
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                    request.setValue("shima/\(current)", forHTTPHeaderField: "User-Agent")
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000 else { throw failure("Couldn’t check GitHub. Try again later.") }
                    found = try JSONDecoder().decode(AppRelease.self, from: data)
                }
                guard !found.draft, !found.prerelease, let version = found.version, let installed = ReleaseVersion(current) else { throw failure("The release version could not be read.") }
                guard version > installed else { message = "You’re up to date (\(current))."; return }
                release = found
                guard bundleURL.path == "/Applications/Shima.app" else { message = "Shima \(found.displayVersion) is available. Install in Applications to update here."; return }
                guard case .adHoc = signing() else { message = "Shima \(found.displayVersion) is available. Keep using your signed installer to preserve Spotify permission."; return }
                guard found.asset(named: "Shima-\(found.displayVersion).zip") != nil, found.asset(named: "SHA256SUMS") != nil else { message = "Shima \(found.displayVersion) is available. This release needs a manual download."; return }
                guard isWritable("/Applications") else { message = "Shima \(found.displayVersion) is available. Applications isn’t writable; download it manually."; return }
                canInstall = true
                message = "Shima \(found.displayVersion) is available."
            } catch { message = error.localizedDescription }
        }
    }

    func install() {
        guard !busy, canInstall, let release else { return }
        busy = true
        message = "Downloading and verifying…"
        Task {
            defer { busy = false }
            do {
                let target = bundleURL
                let stage = try await Task.detached(priority: .utility) { try await Self.prepare(release, target: target) }.value
                do {
                    let helper = target.appendingPathComponent("Contents/MacOS/ShimaUpdater")
                    guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw failure("Update helper is missing. Reinstall Shima manually.") }
                    let process = Process()
                    process.executableURL = helper
                    process.arguments = [String(ProcessInfo.processInfo.processIdentifier), target.path, stage.path]
                    try process.run()
                    message = "Restarting…"
                    NSApp.terminate(nil)
                } catch { try? FileManager.default.removeItem(at: stage); throw error }
            } catch { message = error.localizedDescription }
        }
    }

    nonisolated static func prepare(_ release: AppRelease, target: URL, fetchAsset: @Sendable (AppRelease.Asset, Int) async throws -> Data = { try await fetch($0, limit: $1) }) async throws -> URL {
        let name = "Shima-\(release.displayVersion).zip"
        guard let zip = release.asset(named: name), let sums = release.asset(named: "SHA256SUMS") else { throw failure("Release files are missing.") }
        let manifest = try await fetchAsset(sums, 16_384)
        let archive = try await fetchAsset(zip, 30_000_000)
        guard let text = String(data: manifest, encoding: .utf8), UpdateValidation.checksum(archive, name: name, manifest: text) else { throw failure("The download’s checksum doesn’t match. Your app has not changed.") }
        let stage = target.deletingLastPathComponent().appendingPathComponent(".shima-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let zipURL = stage.appendingPathComponent("update.zip")
            try archive.write(to: zipURL)
            let listing = try run("/usr/bin/zipinfo", ["-1", zipURL.path])
            let details = try run("/usr/bin/zipinfo", ["-l", zipURL.path])
            guard UpdateValidation.archivePathsAreSafe(listing), !details.split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else { throw failure("The update archive contains unsafe paths.") }
            _ = try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, stage.path])
            let app = stage.appendingPathComponent("Shima.app")
            guard let bundle = Bundle(url: app), bundle.bundleIdentifier == "local.shima",
                  bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == release.displayVersion,
                  FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/Shima").path),
                  FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/ShimaUpdater").path) else { throw failure("This download is not the expected Shima release.") }
            _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
            return stage
        } catch { try? FileManager.default.removeItem(at: stage); throw error }
    }

    nonisolated static func fetch(_ asset: AppRelease.Asset, limit: Int, session: URLSession = .shared) async throws -> Data {
        guard asset.size <= limit else { throw failure("The release file is too large.") }
        var request = URLRequest(url: asset.browser_download_url)
        request.timeoutInterval = 60
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw failure("Couldn’t download the update. Try again later.") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw failure("The release file is too large.") }
            data.append(byte)
        }
        guard data.count == asset.size else { throw failure("The download is incomplete.") }
        return data
    }
}

nonisolated func failure(_ message: String) -> NSError { NSError(domain: "ShimaUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

nonisolated func run(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw failure("Update verification failed (\(URL(fileURLWithPath: executable).lastPathComponent)). Your app has not changed.") }
    return String(decoding: data, as: UTF8.self)
}
