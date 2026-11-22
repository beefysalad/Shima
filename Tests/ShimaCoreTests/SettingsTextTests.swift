import CoreGraphics
import Foundation
import Testing
@testable import ShimaCore

@Suite struct SettingsTextTests {
    func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    let cert = "Apple Development: someone@example.com (TEAMID1234)"

    @Test func spotifyRunning() {
        #expect(SettingsText.spotifyRow(.running) == SpotifyStatusRow(
            kind: .running, title: "Spotify is running", detail: "Automation: allowed, or not asked yet.",
            buttonTitle: "Open Automation Settings…", buttonProminent: false))
    }
    @Test func spotifyNotRunning() {
        let row = SettingsText.spotifyRow(.notRunning)
        #expect(row.kind == .notRunning && row.title == "Spotify is not running" && !row.buttonProminent)
        #expect(row.detail == "shima checks the Automation permission when Spotify runs.")
    }
    @Test func spotifyDeniedIsProminent() {
        let row = SettingsText.spotifyRow(.permissionDenied)
        #expect(row.kind == .permissionDenied && row.title == "shima can't control Spotify" && row.buttonProminent)
        #expect(row.detail == "Allow it in System Settings › Privacy & Security › Automation › Shima.")
        #expect(row.buttonTitle == SettingsText.automationButton)
    }
    @Test func automationURL() {
        #expect(SettingsLinks.automation.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }
    @Test func versionText() {
        #expect(SettingsText.version(short: "0.0.1", build: "1") == "Version 0.0.1 (1)")
        #expect(SettingsText.version(short: "0.0.1", build: nil) == "Version 0.0.1")
        #expect(SettingsText.version(short: nil, build: "1") == "Version unknown")
        #expect(SettingsText.version(short: "", build: nil) == "Version unknown")
    }
    @Test func adHoc() {
        #expect(SettingsText.signing(.adHoc, now: utc("2026-11-22T00:00:00Z")) == "Signed ad hoc (no certificate)")
    }
    @Test func certificateShowsKindAndUTCDay() {
        #expect(SettingsText.signing(.certificate(commonName: cert, notAfter: utc("2027-03-26T08:30:00Z")), now: utc("2026-11-22T00:00:00Z"))
                == "Apple Development certificate expires 2027-03-26")
    }
    @Test func lateUTCTimeStaysOnItsDay() {
        #expect(SettingsText.signing(.certificate(commonName: cert, notAfter: utc("2027-03-26T23:59:00Z")), now: utc("2026-11-22T00:00:00Z"))
                == "Apple Development certificate expires 2027-03-26")
    }
    @Test func expiringSoonShowsDays() {
        #expect(SettingsText.signing(.certificate(commonName: cert, notAfter: utc("2027-03-26T08:30:00Z")), now: utc("2027-03-10T08:30:00Z"))
                == "Apple Development certificate expires 2027-03-26 (in 16 days)")
    }
    @Test func expired() {
        #expect(SettingsText.signing(.certificate(commonName: cert, notAfter: utc("2027-03-26T08:30:00Z")), now: utc("2027-03-27T00:00:00Z"))
                == "Apple Development certificate expired 2027-03-26; Automation must be granted again")
    }
    @Test func unknownSaysSeeDocs() {
        let now = utc("2026-11-22T00:00:00Z")
        #expect(SettingsText.signing(.unreadable, now: now) == "Signing certificate: see docs")
        #expect(SettingsText.signing(.certificate(commonName: cert, notAfter: nil), now: now) == "Signing certificate: see docs")
    }

    @Test func expiryWarningThresholdUsesWholeDaysStrictlyBelowThirty() {
        let expiry = utc("2027-03-26T08:30:00Z")
        let summary = SigningSummary.certificate(commonName: cert, notAfter: expiry)
        #expect(SettingsText.expiryWarningDays == 30)
        #expect(SettingsText.signing(summary, now: expiry.addingTimeInterval(-30 * 86_400))
                == "Apple Development certificate expires 2027-03-26")
        #expect(SettingsText.signing(summary, now: expiry.addingTimeInterval(-30 * 86_400 + 1))
                == "Apple Development certificate expires 2027-03-26 (in 29 days)")
    }

    @Test func exactExpiryIsExpired() {
        let expiry = utc("2027-03-26T08:30:00Z")
        #expect(SettingsText.signing(.certificate(commonName: cert, notAfter: expiry), now: expiry)
                == "Apple Development certificate expired 2027-03-26; Automation must be granted again")
    }

    @Test func remainingDaysAreFlooredIncludingPartialFinalDay() {
        let expiry = utc("2027-03-26T08:30:00Z")
        let summary = SigningSummary.certificate(commonName: cert, notAfter: expiry)
        #expect(SettingsText.signing(summary, now: expiry.addingTimeInterval(-86_400))
                == "Apple Development certificate expires 2027-03-26 (in 1 days)")
        #expect(SettingsText.signing(summary, now: expiry.addingTimeInterval(-1))
                == "Apple Development certificate expires 2027-03-26 (in 0 days)")
    }

    @Test func certificateIdentityAfterColonIsNeverDisplayed() {
        let expiry = utc("2027-03-26T00:00:00Z")
        let summary = SigningSummary.certificate(commonName: "Developer ID Application: private@example.com (PRIVATE): additional", notAfter: expiry)
        for now in [utc("2026-11-22T00:00:00Z"), expiry.addingTimeInterval(-1), expiry] {
            let text = SettingsText.signing(summary, now: now)
            #expect(text.hasPrefix("Developer ID Application certificate "))
            #expect(!text.contains("private@example.com"))
            #expect(!text.contains("PRIVATE"))
            #expect(!text.contains("additional"))
        }
    }

    @Test func versionWithEmptyBuildOmitsParentheses() {
        #expect(SettingsText.version(short: "0.0.1", build: "") == "Version 0.0.1")
    }
}

@Suite struct SettingsLayoutTests {
    @Test func navigationStaysInsideTheSidebarAndClearOfQuit() {
        let bounds = CGRect(origin: .zero, size: SettingsLayout.size)
        for page in SettingsPage.allCases {
            let rect = SettingsLayout.navigation(page)
            #expect(bounds.contains(rect))
            #expect(rect.maxX < SettingsLayout.sidebarWidth)
            #expect(!rect.intersects(SettingsLayout.quitButton))
        }
        #expect(bounds.contains(SettingsLayout.quitButton))
    }
    @Test func pagesHaveDistinctTitlesAndSymbols() {
        #expect(SettingsPage.allCases.map(\.rawValue) == ["General", "Music", "Updates", "About"])
        #expect(Set(SettingsPage.allCases.map(\.symbol)).count == SettingsPage.allCases.count)
        #expect(SettingsPage.allCases.allSatisfy { !$0.subtitle.isEmpty })
    }
    @Test func diagnosticClickPointsSitInsideContent() {
        let content = CGRect(x: SettingsLayout.sidebarWidth, y: 0,
            width: SettingsLayout.size.width - SettingsLayout.sidebarWidth, height: SettingsLayout.size.height)
        for point in [SettingsLayout.launchAtLoginClick, SettingsLayout.automationClick] + EqualizerMode.allCases.map(SettingsLayout.equalizerClick) {
            #expect(content.contains(point))
        }
    }
}
