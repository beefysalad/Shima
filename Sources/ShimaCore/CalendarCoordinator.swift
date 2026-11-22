import Foundation
import Observation

@Observable @MainActor public final class CalendarCoordinator {
    public private(set) var model: CalendarModel
    @ObservationIgnored private let client: any CalendarClient
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var terminated = false

    public init(client: any CalendarClient, calendar: Calendar, now: @escaping @MainActor () -> Date) {
        self.client = client
        self.now = now
        self.model = CalendarModel(calendar: calendar, now: now(),
                                   eventsAccess: client.eventsAccess, remindersAccess: client.remindersAccess)
        client.onStoreChanged = { [weak self] in self?.storeChanged() }
        client.onDayChanged = { [weak self] in self?.dayChanged() }
    }

    public var currentDate: Date { now() }

    public func setContext(mode: IslandMode, tab: IslandTab, screenAvailable: Bool) {
        guard !terminated else { return }
        updateAccess()
        let wasVisible = model.isVisible
        let effects = model.setContext(mode: mode, tab: tab, screenAvailable: screenAvailable, now: now())
        if wasVisible && !model.isVisible { loadGeneration &+= 1 }
        perform(effects)
    }

    public func refreshAccess() {
        guard !terminated else { return }
        refreshAccess(events: client.eventsAccess, reminders: client.remindersAccess)
    }

    private func refreshAccess(events: CalendarAccess, reminders: CalendarAccess) {
        let previousEvents = model.eventsAccess
        let previousReminders = model.remindersAccess
        let effects = model.setAccess(events: events, reminders: reminders, now: now())
        if previousEvents != model.eventsAccess || previousReminders != model.remindersAccess {
            loadGeneration &+= 1
        }
        perform(effects)
    }

    public func selectDay(_ day: Date) {
        model.selectDay(day)
    }

    public func showMonth(offset: Int) {
        perform(model.showMonth(offset: offset))
    }

    public func goToToday() {
        guard !terminated else { return }
        perform(model.goToToday(now: now()))
    }

    public func complete(_ item: ReminderItem) {
        let original = model.reminders.first { $0.id == item.id }
        perform(model.completeReminder(id: item.id), restoring: original)
    }

    public func shutdown() {
        terminated = true
        loadGeneration &+= 1
        _ = model.shutdown()
        client.onStoreChanged = nil
        client.onDayChanged = nil
    }

    private func storeChanged() {
        guard !terminated else { return }
        updateAccess()
        perform(model.markStale())
    }

    private func dayChanged() {
        guard !terminated else { return }
        updateAccess()
        perform(model.dayChanged(now: now()))
    }

    private func updateAccess() {
        if model.updateAccess(events: client.eventsAccess, reminders: client.remindersAccess) {
            loadGeneration &+= 1
        }
    }

    private func perform(_ effects: [CalendarEffect], restoring reminder: ReminderItem? = nil) {
        // Reserve the generation before starting a request. A synchronous access
        // callback can reconcile a newer load before this batch reaches its load.
        let schedulesLoad = effects.contains { effect in
            if case .load = effect { return true }
            return false
        }
        if schedulesLoad { loadGeneration &+= 1 }
        let generation = loadGeneration
        for effect in effects {
            guard model.isVisible else { return }
            switch effect {
            case .requestEventsAccess:
                model.eventsRequestInFlight = true
                client.requestEventsAccess { [weak self] _ in
                    guard let self, !self.terminated else { return }
                    self.model.eventsRequestInFlight = false
                    self.refreshAccess()
                }
            case .requestRemindersAccess:
                client.requestRemindersAccess { [weak self] _ in self?.refreshAccess() }
            case .load(let range):
                guard generation == loadGeneration else { continue }
                load(range, generation: generation)
            case .completeReminder(let id):
                if client.complete(reminderID: id) {
                    perform(model.markStale())
                } else if let reminder {
                    model.completionFailed(reminder)
                }
            }
        }
    }

    private func load(_ range: DateInterval, generation: Int) {
        let events = model.eventsAccess == .authorized ? client.events(in: range) : []
        guard generation == loadGeneration, model.isVisible else { return }
        if model.remindersAccess == .authorized {
            client.loadReminders { [weak self] reminders in
                self?.publish(events: events, reminders: reminders, range: range, generation: generation)
            }
        } else {
            publish(events: events, reminders: [], range: range, generation: generation)
        }
    }

    private func publish(events: [CalendarEvent], reminders: [ReminderItem], range: DateInterval, generation: Int) {
        guard model.isVisible, loadGeneration == generation else { return }
        // Authorization can change before the store change notification arrives.
        let eventsAccess = client.eventsAccess
        let remindersAccess = client.remindersAccess
        guard eventsAccess == model.eventsAccess, remindersAccess == model.remindersAccess else {
            refreshAccess(events: eventsAccess, reminders: remindersAccess)
            return
        }
        model.dataLoaded(events: events, reminders: reminders, range: range)
    }
}
