import Foundation
import Testing
@testable import ShimaCore
@testable import Shima

@MainActor struct AppUpdaterTests {
    @Test func startsIdleWithoutCheckingForARelease() {
        let updater = AppUpdater(currentVersion: "1.0.0",
                                 bundleURL: URL(fileURLWithPath: "/Applications/Shima.app"),
                                 signing: { .adHoc },
                                 loadRelease: {
                                     Issue.record("An idle updater must not load a release")
                                     throw URLError(.cannotConnectToHost)
                                 })
        #expect(updater.message == "Check GitHub for a new release.")
        #expect(!updater.busy)
        #expect(updater.release == nil)
        #expect(!updater.canInstall)
    }
}

extension AppUpdaterTests {
    private func waitForCheck(_ updater: AppUpdater) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while updater.busy, ContinuousClock.now < deadline { await Task.yield() }
        #expect(!updater.busy, "The injected release check must finish")
    }

    @Test func rejectsDraftPrereleaseAndUnreadableVersions() async throws {
        for release in [try updateRelease(draft: true), try updateRelease(prerelease: true), try updateRelease(tag: "latest")] {
            let updater = AppUpdater(currentVersion: "1.0.0", signing: { .adHoc }, loadRelease: { release })
            updater.check()
            try await waitForCheck(updater)
            #expect(!updater.canInstall && updater.release == nil)
            #expect(updater.message == "The release version could not be read.")
        }
        let release = try updateRelease()
        let updater = AppUpdater(currentVersion: "invalid", signing: { .adHoc }, loadRelease: { release })
        updater.check()
        try await waitForCheck(updater)
        #expect(updater.release == nil && !updater.canInstall)
        #expect(updater.message == "The release version could not be read.")
    }

    @Test func equalAndOlderReleasesAreUpToDate() async throws {
        for current in ["1.1.0", "2.0.0"] {
            let release = try updateRelease()
            let updater = AppUpdater(currentVersion: current, signing: { .adHoc }, loadRelease: { release })
            updater.check()
            try await waitForCheck(updater)
            #expect(updater.message == "You’re up to date (\(current)).")
            #expect(updater.release == nil && !updater.canInstall)
        }
    }

    @Test func sourceBuildCannotInstallAndDoesNotReadSigning() async throws {
        let release = try updateRelease()
        let updater = AppUpdater(currentVersion: "1.0.0", bundleURL: URL(fileURLWithPath: "/source/Shima.app"),
                                 signing: { Issue.record("Source builds must stop before signing lookup"); return .adHoc },
                                 loadRelease: { release })
        updater.check()
        try await waitForCheck(updater)
        #expect(!updater.canInstall && updater.release?.tag_name == "v1.1.0")
        #expect(updater.message == "Shima 1.1.0 is available. Install in Applications to update here.")
    }

    @Test func certificateAndUnreadableSigningRequireManualInstaller() async throws {
        for signing in [SigningSummary.certificate(commonName: "Fixture", notAfter: nil), .unreadable] {
            let release = try updateRelease()
            let updater = AppUpdater(currentVersion: "1.0.0", bundleURL: URL(fileURLWithPath: "/Applications/Shima.app"),
                                     signing: { signing }, loadRelease: { release })
            updater.check()
            try await waitForCheck(updater)
            #expect(!updater.canInstall && updater.release?.tag_name == "v1.1.0")
            #expect(updater.message == "Shima 1.1.0 is available. Keep using your signed installer to preserve Spotify permission.")
        }
    }

    @Test func eitherMissingReleaseAssetRequiresManualDownload() async throws {
        for assets in [["Shima-1.1.0.zip"], ["SHA256SUMS"], []] {
            let release = try updateRelease(assets: assets)
            let updater = AppUpdater(currentVersion: "1.0.0", bundleURL: URL(fileURLWithPath: "/Applications/Shima.app"),
                                     signing: { .adHoc }, loadRelease: { release })
            updater.check()
            try await waitForCheck(updater)
            #expect(!updater.canInstall)
            #expect(updater.message == "Shima 1.1.0 is available. This release needs a manual download.")
        }
    }

    @Test func failedChecksClearBusyAndCanBeRetried() async throws {
        let updater = AppUpdater(currentVersion: "1.0.0", loadRelease: { throw URLError(.notConnectedToInternet) })
        updater.check()
        #expect(updater.busy && updater.message == "Checking for updates…")
        updater.check() // Coalesces while the first task is waiting to run on the main actor.
        try await waitForCheck(updater)
        #expect(!updater.canInstall && updater.release == nil)
        #expect(updater.message == URLError(.notConnectedToInternet).localizedDescription)
        updater.check()
        #expect(updater.busy)
        try await waitForCheck(updater)
    }

    @Test func availableReleaseRespectsCurrentApplicationsWritability() async throws {
        let release = try updateRelease()
        let updater = AppUpdater(currentVersion: "1.0.0", bundleURL: URL(fileURLWithPath: "/Applications/Shima.app"),
                                 signing: { .adHoc }, loadRelease: { release })
        updater.check()
        try await waitForCheck(updater)
        #expect(updater.canInstall == FileManager.default.isWritableFile(atPath: "/Applications"))
        #expect(updater.message == (updater.canInstall ? "Shima 1.1.0 is available." :
            "Shima 1.1.0 is available. Applications isn’t writable; download it manually."))
    }
}

extension AppUpdaterTests {
    @Test func applicationsWritabilityControlsInstallWithoutChangingTheFilesystem() async throws {
        let release = try updateRelease()
        for writable in [false, true] {
            var checkedPaths: [String] = []
            let updater = AppUpdater(currentVersion: "1.0.0", bundleURL: URL(fileURLWithPath: "/Applications/Shima.app"),
                                     signing: { .adHoc }, loadRelease: { release },
                                     isWritable: { path in checkedPaths.append(path); return writable })
            updater.check()
            try await waitForCheck(updater)
            #expect(checkedPaths == ["/Applications"])
            #expect(updater.canInstall == writable)
            #expect(updater.release?.tag_name == "v1.1.0")
            #expect(updater.message == (writable ? "Shima 1.1.0 is available." :
                "Shima 1.1.0 is available. Applications isn’t writable; download it manually."))
        }
    }
}
