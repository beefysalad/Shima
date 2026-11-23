import AppKit
import Testing
@testable import Shima
@testable import ShimaCore

@MainActor private final class TestScheduler: Scheduler {
    @MainActor final class Task: ScheduledTask {
        var cancelled = false
        func cancel() { cancelled = true }
    }
    var scheduled: [(delay: Duration, action: @MainActor () -> Void, task: Task)] = []
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let task = Task()
        scheduled.append((delay, action, task))
        return task
    }
    func fire() {
        let due = scheduled.filter { !$0.task.cancelled }
        scheduled.removeAll()
        for entry in due { entry.action() }
    }
}

@MainActor private final class Board {
    let pb = NSPasteboard(name: NSPasteboard.Name("local.shima.test.\(UUID().uuidString)"))
    isolated deinit { pb.releaseGlobally() }
}

@MainActor struct ShelfPasteboardTests {
    @Test func fileWritesFileURL() throws {
        let board = Board()
        let url = URL(fileURLWithPath: "/tmp/shima-test-file.txt")
        ShelfPasteboard.write(ShelfItem(kind: .file(url)), to: board.pb)
        let read = board.pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        #expect(read?.map(\.path) == [url.path])
    }

    @Test func textWritesPlainString() {
        let board = Board()
        ShelfPasteboard.write(ShelfItem(kind: .text("hello")), to: board.pb)
        #expect(board.pb.string(forType: .string) == "hello")
    }

    @Test func linkWritesURLAndString() throws {
        let board = Board()
        let url = try #require(URL(string: "https://example.com/a"))
        ShelfPasteboard.write(ShelfItem(kind: .link(url)), to: board.pb)
        #expect(board.pb.string(forType: .string) == "https://example.com/a")
        let read = board.pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        #expect(read?.first?.absoluteString == "https://example.com/a")
    }

    @Test func isAvailableFalseForMissingFile() {
        let missing = ShelfItem(kind: .file(URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")))
        #expect(!ShelfPasteboard.isAvailable(missing))
        #expect(ShelfPasteboard.isAvailable(ShelfItem(kind: .text("x"))))
        #expect(ShelfPasteboard.isAvailable(ShelfItem(kind: .file(URL(fileURLWithPath: "/tmp")))))
    }

    @Test func missingFileIsRemovedInsteadOfDragging() {
        let store = ShelfStore()
        let item = ShelfItem(kind: .file(URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")))
        let view = ShelfChipDragView(scheduler: TestScheduler())
        view.item = item
        var removed: [UUID] = []
        view.onMissing = { removed.append($0); store.remove(id: $0) }
        #expect(!view.prepareDrag())
        #expect(removed == [item.id])
        let ok = ShelfChipDragView(scheduler: TestScheduler())
        ok.item = ShelfItem(kind: .text("x"))
        #expect(ok.prepareDrag())
    }

    @Test func ownDragFlagSetOnBeginAndClearedOnEnd() {
        let view = ShelfChipDragView(scheduler: TestScheduler())
        view.item = ShelfItem(kind: .text("x"))
        OwnDrag.active = false
        view.sessionWillBegin()
        #expect(OwnDrag.active)
        view.sessionEnded(operation: .copy)
        #expect(!OwnDrag.active)
    }

    @Test func dragStartedCallbackFiresOnceAfterDelay() {
        let scheduler = TestScheduler()
        let view = ShelfChipDragView(scheduler: scheduler)
        view.item = ShelfItem(kind: .text("x"))
        var calls = 0
        view.onDragStarted = { calls += 1 }
        view.sessionWillBegin()
        #expect(scheduler.scheduled.count == 1)
        #expect(scheduler.scheduled[0].delay == .milliseconds(250))
        #expect(calls == 0)
        scheduler.fire()
        scheduler.fire()
        #expect(calls == 1)
        view.sessionEnded(operation: [])
    }
}
