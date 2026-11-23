import Foundation
import Testing
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
