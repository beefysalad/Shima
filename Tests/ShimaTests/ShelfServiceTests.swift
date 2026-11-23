import Foundation
import Testing
@testable import Shima
@testable import ShimaCore

@MainActor private final class TestScheduler: Scheduler {
    @MainActor final class Task: ScheduledTask {
        var cancelled = false
        func cancel() { cancelled = true }
    }
    var scheduled: [(delay: Duration, action: @MainActor () -> Void, task: Task)] = []
    var pending: Int { scheduled.filter { !$0.task.cancelled }.count }

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let task = Task()
        scheduled.append((delay, action, task))
        return task
    }

    /// Runs every uncancelled task once.
    func fire() {
        let due = scheduled.filter { !$0.task.cancelled }
        scheduled.removeAll()
        for entry in due { entry.action() }
    }
}

@MainActor struct ShelfServiceTests {
    private func make(fake: Bool = true) -> (ShelfService, TestScheduler) {
        let scheduler = TestScheduler()
        let service = ShelfService(environment: fake ? ["SHIMA_FAKE_SHELF": "1"] : [:], scheduler: scheduler)
        return (service, scheduler)
    }

    private func send(_ service: ShelfService, _ command: String) throws {
        let selector = NSSelectorFromString("fakeControl:")
        try #require(service.responds(to: selector))
        _ = service.perform(selector, with: Notification(name: .init("local.shima.fake-shelf"), object: command))
    }

    @Test func fakeCommandsQueueThenDropMutatesStore() throws {
        let (service, _) = make()
        defer { service.shutdown() }
        var dropped = 0
        service.onDropped = { dropped += 1 }
        try send(service, "ping")
        try send(service, "add-file /tmp/shima-shelf-a.txt")
        try send(service, "add-text hello world")
        try send(service, "add-link https://example.com")
        #expect(service.store.items.isEmpty)
        try send(service, "drop")
        #expect(service.store.items.count == 3)
        #expect(service.status == "Added 3")
        #expect(dropped == 1)
        try send(service, "drop")
        #expect(service.store.items.count == 3)
        try send(service, "clear")
        #expect(service.store.items.isEmpty)
    }

    @Test func dropWhileFullReportsRefusedAndStatusText() {
        let (service, _) = make(fake: false)
        let fill = (0..<ShelfStore.cap).map { DroppedEntry(string: "item \($0)") }
        service.drop(fill)
        let result = service.drop([DroppedEntry(string: "a"), DroppedEntry(string: "b")])
        #expect(result == ShelfAddResult(added: 0, refused: 2))
        #expect(service.status == "Added 0, 2 did not fit")
    }

    @Test func emptyDropSetsNoStatus() {
        let (service, scheduler) = make(fake: false)
        var dropped = false
        service.onDropped = { dropped = true }
        service.drop([])
        #expect(service.status == nil && !dropped && scheduler.pending == 0)
    }

    @Test func statusClearsAfterOneShotTimer() {
        let (service, scheduler) = make(fake: false)
        #expect(scheduler.pending == 0)
        service.drop([DroppedEntry(string: "x")])
        #expect(service.status == "Added 1")
        #expect(scheduler.pending == 1)
        #expect(scheduler.scheduled.last?.delay == .milliseconds(2200))
        scheduler.fire()
        #expect(service.status == nil)
        #expect(scheduler.pending == 0)
    }

    @Test func newDropReplacesPendingStatusClear() {
        let (service, scheduler) = make(fake: false)
        service.drop([DroppedEntry(string: "x")])
        service.drop([DroppedEntry(string: "y")])
        #expect(scheduler.pending == 1)
        #expect(scheduler.scheduled.first?.task.cancelled == true)
        #expect(service.status == "Added 1")
        scheduler.fire()
        #expect(service.status == nil)
    }

    @Test func dragCommandsForwardEvents() throws {
        let (service, _) = make()
        defer { service.shutdown() }
        var events: [ShelfDragEvent] = []
        service.onDragEvent = { events.append($0) }
        try send(service, "drag-enter")
        try send(service, "drag-exit")
        try send(service, "add-text hi")
        try send(service, "drop")
        #expect(events == [.entered, .exited, .ended(dropped: true)])
    }

    @Test func dropCancelClearsPendingWithoutAdding() throws {
        let (service, _) = make()
        defer { service.shutdown() }
        var events: [ShelfDragEvent] = []
        service.onDragEvent = { events.append($0) }
        try send(service, "add-text hi")
        try send(service, "drop-cancel")
        try send(service, "drop")
        #expect(service.store.items.isEmpty)
        #expect(events == [.ended(dropped: false), .ended(dropped: true)])
    }

    @Test func shutdownRemovesObserver() {
        let (service, _) = make()
        #expect(service.isObservingFake)
        service.shutdown()
        #expect(!service.isObservingFake)
        let (real, _) = make(fake: false)
        #expect(!real.isObservingFake)
    }
}
