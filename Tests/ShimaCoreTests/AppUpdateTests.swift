import Foundation
import Testing
@testable import ShimaCore

@Suite struct AppUpdateTests {
    @Test func versionsCompareNumericallyAndRejectUnstableTags() {
        #expect(ReleaseVersion("v0.1.10")! > ReleaseVersion("0.1.9")!)
        #expect(ReleaseVersion("1.0.0")! > ReleaseVersion("0.99.99")!)
        for bad in ["", "latest", "1.2", "1.2.3-beta", "1.-2.3", "1.2.3/other", "999999999999999999999999.0.0"] {
            #expect(ReleaseVersion(bad) == nil)
        }
    }
    @Test func checksumsRejectTamperingMissingOrAmbiguousEntries() {
        let data = Data("hello".utf8)
        let line = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824  Shima.zip\n"
        #expect(UpdateValidation.checksum(data, name: "Shima.zip", manifest: line))
        #expect(!UpdateValidation.checksum(Data("changed".utf8), name: "Shima.zip", manifest: line))
        #expect(!UpdateValidation.checksum(data, name: "Other.zip", manifest: line))
        #expect(!UpdateValidation.checksum(data, name: "Shima.zip", manifest: line + line))
    }
    @Test func archivesCannotEscapeTheStagingDirectory() {
        #expect(UpdateValidation.archivePathsAreSafe("Shima.app/\nShima.app/Contents/MacOS/Shima\n__MACOSX/Shima.app/._Contents"))
        for bad in ["", "/Applications/Shima.app/x", "Shima.app/../../outside", "Other.app/file", "Shima.app\\outside"] {
            #expect(!UpdateValidation.archivePathsAreSafe(bad))
        }
    }
    @Test func onlyTheExpectedReleaseAssetHostAndPathAreAccepted() throws {
        func release(_ url: String, draft: Bool = false) throws -> AppRelease {
            let json = """
            {"tag_name":"v0.1.4","draft":\(draft),"prerelease":false,"assets":[{"name":"Shima-0.1.4.zip","size":42,"browser_download_url":"\(url)"}]}
            """
            return try JSONDecoder().decode(AppRelease.self, from: Data(json.utf8))
        }
        let good = "https://github.com/beefysalad/Shima/releases/download/v0.1.4/Shima-0.1.4.zip"
        #expect(try release(good).asset(named: "Shima-0.1.4.zip") != nil)
        for url in [good.replacingOccurrences(of: "https:", with: "http:"), good.replacingOccurrences(of: "github.com", with: "github.com.evil.test"), good.replacingOccurrences(of: "beefysalad", with: "other")] {
            #expect(try release(url).asset(named: "Shima-0.1.4.zip") == nil)
        }
        #expect(try release(good, draft: true).asset(named: "Shima-0.1.4.zip") == nil)
    }
    @Test func failedReplacementRestoresTheOldApp() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let old = folder.appendingPathComponent("Shima.app"), staged = folder.appendingPathComponent("Missing.app"), backup = folder.appendingPathComponent("Previous.app")
        try Data("old app".utf8).write(to: old)
        #expect(throws: (any Error).self) { try UpdateSwap.install(staged: staged, target: old, backup: backup) }
        #expect(try Data(contentsOf: old) == Data("old app".utf8))
        #expect(!fm.fileExists(atPath: backup.path))
    }
    @Test func successfulReplacementKeepsTheOldAppForRecovery() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let target = folder.appendingPathComponent("Shima.app"), staged = folder.appendingPathComponent("New.app"), backup = folder.appendingPathComponent("Previous.app")
        try Data("old".utf8).write(to: target)
        try Data("new".utf8).write(to: staged)
        try UpdateSwap.install(staged: staged, target: target, backup: backup)
        #expect(try Data(contentsOf: target) == Data("new".utf8))
        #expect(try Data(contentsOf: backup) == Data("old".utf8))
    }
}
