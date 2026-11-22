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
    /// scripts/verify-settings.sh copies these numbers; change both together.
    @Test func sizeAndClickPointsArePinned() {
        #expect(SettingsLayout.size == CGSize(width: 440, height: 510))
        #expect(SettingsLayout.launchAtLoginClick == CGPoint(x: 28, y: 50))
        #expect(EqualizerMode.allCases.map { SettingsLayout.center(SettingsLayout.equalizerSegment($0)) }
                == [CGPoint(x: 185, y: 108), CGPoint(x: 275, y: 108), CGPoint(x: 365, y: 108)])
        #expect(SettingsLayout.center(SettingsLayout.automationButton) == CGPoint(x: 135, y: 240))
        #expect(SettingsLayout.center(SettingsLayout.quitButton) == CGPoint(x: 370, y: 484))
    }
    @Test func controlsFitAndDoNotOverlap() {
        let bounds = CGRect(origin: .zero, size: SettingsLayout.size)
        let rects = SettingsLayout.allRects
        #expect(rects.count == 17)
        for r in rects { #expect(bounds.contains(r)) }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || overlap.width * overlap.height == 0, "rects \(i) and \(j) overlap")
            }
        }
    }
    @Test func segmentsAreEqualAndAdjacent() {
        let s = EqualizerMode.allCases.map(SettingsLayout.equalizerSegment)
        #expect(s.allSatisfy { $0.size == CGSize(width: 90, height: 28) })
        #expect(s[0].maxX == s[1].minX && s[1].maxX == s[2].minX && s[0].minX > SettingsLayout.equalizerLabel.maxX)
    }
}
