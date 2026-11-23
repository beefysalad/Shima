import CryptoKit
import Foundation
import Testing
@testable import Shima
@testable import ShimaCore

struct AppUpdaterPrepareTests {
    private func fixtureRoot() throws -> URL {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repo.appendingPathComponent(".build/updater-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func archive(at root: URL, scenario: String) throws -> Data {
        let script = """
        import plistlib, stat, sys, zipfile
        path, scenario = sys.argv[1:]
        with zipfile.ZipFile(path, 'w') as archive:
            def entry(name, data, mode=stat.S_IFREG | 0o755):
                item = zipfile.ZipInfo(name)
                item.create_system = 3
                item.external_attr = mode << 16
                archive.writestr(item, data)
            if scenario == 'unsafe':
                entry('Shima.app/../../outside', b'unsafe')
            elif scenario == 'symlink':
                entry('Shima.app/Contents/link', b'../../../outside', stat.S_IFLNK | 0o777)
            elif scenario == 'malformed':
                entry('Shima.app/Contents/Info.plist', b'not a plist')
            else:
                entry('Shima.app/Contents/Info.plist', plistlib.dumps({
                    'CFBundleIdentifier': 'other.app' if scenario == 'wrongID' else 'local.shima',
                    'CFBundleShortVersionString': '9.9.9' if scenario == 'wrongVersion' else '1.1.0',
                    'CFBundleExecutable': 'Shima', 'CFBundlePackageType': 'APPL'}), stat.S_IFREG | 0o644)
                for name in ['Shima', 'ShimaUpdater']:
                    if scenario == 'missing' + name: continue
                    mode = 0o644 if scenario == 'notExecutable' + name else 0o755
                    entry('Shima.app/Contents/MacOS/' + name, b'#!/bin/sh\\nexit 0\\n', stat.S_IFREG | mode)
        """
        let path = root.appendingPathComponent("fixture.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script, path.path, scenario]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        return try Data(contentsOf: path)
    }

    private func manifest(for archive: Data) -> Data {
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        return Data("\(digest)  Shima-1.1.0.zip\n".utf8)
    }

    private func assertRejected(scenario: String, message: String, badManifest: Bool = false) async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Shima.app")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let marker = target.appendingPathComponent("original")
        try Data("installed app".utf8).write(to: marker)
        let zip = try archive(at: root, scenario: scenario)
        let sums = badManifest ? Data("wrong checksum".utf8) : manifest(for: zip)
        let release = try updateRelease()
        do {
            _ = try await AppUpdater.prepare(release, target: target) { asset, limit in
                #expect(limit == (asset.name == "SHA256SUMS" ? 16_384 : 30_000_000))
                return asset.name == "SHA256SUMS" ? sums : zip
            }
            Issue.record("Invalid fixture was accepted: \(scenario)")
        } catch {
            #expect(error.localizedDescription.contains(message))
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(!entries.contains { $0.hasPrefix(".shima-update-") }, "Rejected archives must leave no staging directory")
        #expect(try Data(contentsOf: marker) == Data("installed app".utf8))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("outside").path))
    }

    @Test func checksumMismatchDoesNotCreateAStageOrChangeInstalledApp() async throws {
        try await assertRejected(scenario: "unsigned", message: "checksum", badManifest: true)
    }

    @Test(arguments: ["unsafe", "symlink"])
    func unsafeArchivePathsAndSymlinksAreRejectedAndCleaned(scenario: String) async throws {
        try await assertRejected(scenario: scenario, message: "unsafe paths")
    }

    @Test(arguments: ["wrongID", "wrongVersion", "missingShima", "missingShimaUpdater",
                      "notExecutableShima", "notExecutableShimaUpdater", "malformed"])
    func unexpectedBundlesAreRejectedAndCleaned(scenario: String) async throws {
        try await assertRejected(scenario: scenario, message: "not the expected Shima release")
    }

    @Test func invalidCodeSignatureIsRejectedAndCleaned() async throws {
        try await assertRejected(scenario: "unsigned", message: "codesign")
    }

    @Test func missingAssetsAndFetchFailuresDoNotCreateStages() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Shima.app")
        let noAssets = try updateRelease(assets: [])
        do {
            _ = try await AppUpdater.prepare(noAssets, target: target) { _, _ in
                Issue.record("Missing assets must fail before downloading")
                return Data()
            }
            Issue.record("Missing assets were accepted")
        } catch { #expect(error.localizedDescription == "Release files are missing.") }
        let release = try updateRelease()
        for failManifest in [true, false] {
            do {
                _ = try await AppUpdater.prepare(release, target: target) { asset, _ in
                    if failManifest || asset.name != "SHA256SUMS" { throw URLError(.networkConnectionLost) }
                    return Data("manifest".utf8)
                }
                Issue.record("Fetch failure was ignored")
            } catch { #expect((error as? URLError)?.code == .networkConnectionLost) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }
}
