import CoreGraphics
import Foundation
import Testing
@testable import ShimaCore

struct CoreAuditTests {
    @Test func settingsDiagnosticCenterPreservesRectOriginAndDimensions() {
        #expect(SettingsLayout.center(CGRect(x: -20, y: 15, width: 80, height: 30)) == CGPoint(x: 20, y: 30))
        #expect(SettingsLayout.center(.zero) == .zero)
    }

    @Test func releasePageKeepsItsVersionTag() throws {
        let data = Data(#"{"tag_name":"v1.2.3","draft":false,"prerelease":false,"assets":[]}"#.utf8)
        let release = try JSONDecoder().decode(AppRelease.self, from: data)
        #expect(release.page.absoluteString == "https://github.com/beefysalad/Shima/releases/tag/v1.2.3")
    }

    @Test func monthWithoutLocaleStillBuildsAnUppercaseTitleAndCompleteGrid() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = nil
        let day = Date(timeIntervalSince1970: 1_791_072_000)
        let grid = MonthGrid.make(month: day, today: day, calendar: calendar)
        calendar.locale = .current
        let expected = MonthGrid.make(month: day, today: day, calendar: calendar)
        #expect(!grid.title.isEmpty && grid.title == grid.title.uppercased(with: .current))
        #expect(grid.visibleRange == expected.visibleRange)
        #expect(grid.weeks.flatMap { $0 }.map(\.date) == expected.weeks.flatMap { $0 }.map(\.date))
    }

    @Test func missingCertificateCommonNameStillDisplaysItsExpiry() {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let text = SettingsText.signing(.certificate(commonName: "", notAfter: expiry),
                                        now: expiry.addingTimeInterval(-60 * 86_400))
        #expect(text == " certificate expires \(SettingsText.utcDay(expiry))")
    }

    @Test func hiddenAndTerminatedCalendarModelIgnoresNavigationAndDayChanges() {
        let calendar = calendarTestCalendar()
        let now = calendarTestDate(2026, 10, 25)
        var model = CalendarModel(calendar: calendar, now: now)
        model.selectDay(now.addingTimeInterval(86_400))
        #expect(model.selectedDay == calendar.startOfDay(for: now))
        #expect(model.goToToday(now: now.addingTimeInterval(86_400)).isEmpty)
        _ = model.shutdown()
        let stopped = model
        #expect(model.dayChanged(now: now.addingTimeInterval(86_400)).isEmpty)
        #expect(model == stopped)
    }
}

@MainActor struct CoreActorAuditTests {
    @Test func removingAnObserverLeavesOtherSubscriptionsActive() {
        let state = AppState()
        var removed: [IslandTab] = []
        var retained: [IslandTab] = []
        let token = state.addTabContextObserver { _, tab in removed.append(tab) }
        state.addTabContextObserver { _, tab in retained.append(tab) }
        state.removeTabContextObserver(token)
        state.removeTabContextObserver(token)
        state.removeTabContextObserver(UUID())
        state.selectedTab = .calendar
        #expect(removed == [.music])
        #expect(retained == [.music, .calendar])
    }

    @Test func fakeSpotifyDefaultClockTimestampsItsReading() throws {
        let before = Date()
        let client = FakeSpotifyClient(state: .playing)
        var readingDate: Date?
        client.onEvent = { event in
            if case let .reading(reading, source, date) = event {
                #expect(reading.trackID == "fake:1" && source == .script)
                readingDate = date
            }
        }
        client.refresh()
        let date = try #require(readingDate)
        #expect(date >= before && date <= Date())
    }

    @Test func settingsDefaultClockDeterminesCertificateWarning() {
        let expiry = Date().addingTimeInterval(5.5 * 86_400)
        let model = SettingsModel(state: AppState(), store: SettingsStore(storage: InMemoryPreferenceStorage()),
                                  loginItems: FakeLoginItemService(status: .notRegistered), versionText: "Fixture",
                                  readSigning: { .certificate(commonName: "Fixture", notAfter: expiry) })
        model.refresh()
        #expect(model.signingText == "Fixture certificate expires \(SettingsText.utcDay(expiry)) (in 5 days)")
    }
}
