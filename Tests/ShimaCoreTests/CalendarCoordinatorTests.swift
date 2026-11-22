import Foundation
import Testing
@testable import ShimaCore

@MainActor struct CalendarCoordinatorTests {
    private let now = calendarTestDate(2026, 10, 25)

    @Test func permissionAskedOnlyOnFirstOpen() {
        let client = FakeCalendarClient()
        let coordinator = makeCoordinator(client)
        coordinator.setContext(mode: .expanded, tab: .music, screenAvailable: true)
        #expect(client.eventsRequestCount == 0 && client.remindersRequestCount == 0)
        #expect(client.eventsReadCount == 0 && client.loadCount == 0)
        open(coordinator)
        #expect(client.eventsRequestCount == 1 && client.remindersRequestCount == 1)
        #expect(client.eventsReadCount == 1 && client.loadCount == 1)
        close(coordinator)
        open(coordinator)
        #expect(client.eventsRequestCount == 1 && client.remindersRequestCount == 1)
        #expect(client.eventsReadCount == 1 && client.loadCount == 1)
    }

    @Test func pendingPermissionDoesNotPromptOrReadWhileHidden() {
        let client = FakeCalendarClient(requestResult: nil)
        let coordinator = makeCoordinator(client)
        open(coordinator)
        #expect(client.eventsRequestCount == 1 && client.remindersRequestCount == 0)
        client.eventsAccess = .authorized
        client.onStoreChanged?()
        #expect(client.remindersRequestCount == 0)
        close(coordinator)
        let readsBeforeCallback = client.eventsReadCount
        client.completePendingAccess(.authorized)
        #expect(client.eventsReadCount == readsBeforeCallback)
        #expect(client.eventsRequestCount == 1 && client.remindersRequestCount == 0)
        open(coordinator)
        #expect(client.eventsRequestCount == 1 && client.remindersRequestCount == 1)
        client.completePendingAccess(.denied)
        #expect(coordinator.model.remindersAccess == .denied)
        #expect(client.loadCount == 0)
    }

    @Test func staleLoadCompletionIsDropped() {
        let client = authorizedClient()
        client.autoCompleteReminders = false
        client.reminders = [calendarTestReminder("older")]
        let coordinator = makeCoordinator(client)
        open(coordinator)
        client.reminders = [calendarTestReminder("newer")]
        coordinator.showMonth(offset: 1)
        #expect(client.loadCount == 2)
        client.completePendingReminders(at: 1)
        client.completePendingReminders()
        #expect(coordinator.model.reminders == [calendarTestReminder("newer")])
    }

    @Test func storeChangeReloadsOnlyWhenVisible() {
        let client = authorizedClient()
        let coordinator = makeCoordinator(client)
        client.onStoreChanged?()
        #expect(client.eventsReadCount == 0 && client.loadCount == 0)
        open(coordinator)
        client.onStoreChanged?()
        #expect(client.eventsReadCount == 2 && client.loadCount == 2)
        close(coordinator)
        client.onStoreChanged?()
        #expect(client.eventsReadCount == 2 && client.loadCount == 2)
        open(coordinator)
        #expect(client.eventsReadCount == 3 && client.loadCount == 3)
    }

    @Test func deniedStoreShowsStateWithoutLoad() {
        let client = FakeCalendarClient(eventsAccess: .denied, remindersAccess: .denied)
        let coordinator = makeCoordinator(client)
        open(coordinator)
        #expect(coordinator.model.eventsAccess == .denied && coordinator.model.remindersAccess == .denied)
        #expect(client.eventsReadCount == 0 && client.loadCount == 0)
    }

    @Test func completeFailureRestores() {
        let client = authorizedClient()
        let reminder = calendarTestReminder("complete")
        client.reminders = [reminder]
        client.completionResult = false
        let coordinator = makeCoordinator(client)
        open(coordinator)
        coordinator.complete(reminder)
        #expect(client.completedIDs == [reminder.id])
        #expect(coordinator.model.reminders == [reminder])
    }

    @Test func successfulCompletionSupersedesAnInFlightRead() {
        let client = authorizedClient()
        let reminder = calendarTestReminder("complete")
        client.reminders = [reminder]
        let coordinator = makeCoordinator(client)
        open(coordinator)
        client.autoCompleteReminders = false
        client.onStoreChanged?()
        coordinator.complete(reminder)
        client.completePendingReminders()
        #expect(coordinator.model.reminders.isEmpty)
        client.completePendingReminders()
        #expect(coordinator.model.reminders.isEmpty)
    }

    @Test(arguments: [false, true])
    func hidingInvalidatesPendingLoadAndReopenReplacesIt(completeAfterReopening: Bool) {
        let client = authorizedClient()
        client.autoCompleteReminders = false
        client.reminders = [calendarTestReminder("before hide")]
        let coordinator = makeCoordinator(client)
        open(coordinator)
        close(coordinator)
        if !completeAfterReopening {
            client.completePendingReminders()
            #expect(coordinator.model.reminders.isEmpty)
        }
        client.reminders = [calendarTestReminder("after reopen")]
        open(coordinator)
        #expect(client.loadCount == 2)
        client.completePendingReminders(at: completeAfterReopening ? 1 : 0)
        if completeAfterReopening { client.completePendingReminders() }
        #expect(coordinator.model.reminders == [calendarTestReminder("after reopen")])
    }

    @Test func storeChangeRefreshesRevokedAccessWhileHidden() {
        let client = authorizedClient()
        client.reminders = [calendarTestReminder("loaded")]
        let coordinator = makeCoordinator(client)
        open(coordinator)
        #expect(coordinator.model.reminders == client.reminders)
        client.autoCompleteReminders = false
        client.onStoreChanged?()
        close(coordinator)
        client.remindersAccess = .denied
        client.onStoreChanged?()
        #expect(coordinator.model.remindersAccess == .denied)
        #expect(coordinator.model.reminders.isEmpty)
        #expect(client.eventsReadCount == 2 && client.loadCount == 2)
        client.completePendingReminders()
        #expect(coordinator.model.reminders.isEmpty)
    }

    @Test func visibleRevocationReplacesPendingRead() {
        let client = authorizedClient()
        client.autoCompleteReminders = false
        client.events = [CalendarEvent(id: "event", title: "Event", start: now, end: now.addingTimeInterval(60), isAllDay: false, colorRGB: [1, 0, 0])]
        client.reminders = [calendarTestReminder("old")]
        let coordinator = makeCoordinator(client)
        open(coordinator)
        client.eventsAccess = .denied
        client.reminders = [calendarTestReminder("new")]
        client.onStoreChanged?()
        #expect(client.eventsReadCount == 1 && client.loadCount == 2)
        client.completePendingReminders(at: 1)
        client.completePendingReminders()
        #expect(coordinator.model.events.isEmpty)
        #expect(coordinator.model.reminders == [calendarTestReminder("new")])
    }

    @Test func shutdownDiscardsCallbacksAndStopsWork() {
        let client = FakeCalendarClient(eventsAccess: .authorized, remindersAccess: .notDetermined, requestResult: nil)
        let coordinator = makeCoordinator(client)
        open(coordinator)
        #expect(client.remindersRequestCount == 1 && client.eventsReadCount == 1)
        client.remindersAccess = .authorized
        client.autoCompleteReminders = false
        client.reminders = [calendarTestReminder("late")]
        coordinator.refreshAccess()
        #expect(client.loadCount == 1)
        let storeChanged = client.onStoreChanged
        let dayChanged = client.onDayChanged
        coordinator.shutdown()
        client.completePendingReminders()
        client.completePendingAccess(.authorized)
        storeChanged?()
        dayChanged?()
        open(coordinator)
        #expect(client.onStoreChanged == nil && client.onDayChanged == nil)
        #expect(!coordinator.model.isVisible && coordinator.model.reminders.isEmpty)
        #expect(client.eventsReadCount == 2 && client.loadCount == 1)
    }

    private func authorizedClient() -> FakeCalendarClient {
        FakeCalendarClient(eventsAccess: .authorized, remindersAccess: .authorized)
    }

    private func makeCoordinator(_ client: FakeCalendarClient) -> CalendarCoordinator {
        CalendarCoordinator(client: client, calendar: calendarTestCalendar(), now: { now })
    }

    private func open(_ coordinator: CalendarCoordinator) {
        coordinator.setContext(mode: .expanded, tab: .calendar, screenAvailable: true)
    }

    private func close(_ coordinator: CalendarCoordinator) {
        coordinator.setContext(mode: .collapsed, tab: .music, screenAvailable: true)
    }
}
