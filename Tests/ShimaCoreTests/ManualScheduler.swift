import ShimaCore

@MainActor final class ManualScheduler: Scheduler {
    @MainActor final class ManualTask: ScheduledTask {
        var cancelled = false
        func cancel() { cancelled = true }
    }

    private struct Entry {
        let due: Duration
        let seq: Int
        let action: @MainActor () -> Void
        let task: ManualTask
    }

    private(set) var now: Duration = .zero
    private var entries: [Entry] = []
    private var sequence = 0

    var pendingCount: Int { entries.filter { !$0.task.cancelled }.count }

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let task = ManualTask()
        entries.append(Entry(due: now + delay, seq: sequence, action: action, task: task))
        sequence += 1
        return task
    }

    func advance(by duration: Duration) {
        let target = now + duration
        while true {
            entries.removeAll { $0.task.cancelled }
            guard let index = entries.indices.min(by: {
                let lhs = entries[$0]
                let rhs = entries[$1]
                return lhs.due == rhs.due ? lhs.seq < rhs.seq : lhs.due < rhs.due
            }), entries[index].due <= target else { break }
            let entry = entries.remove(at: index)
            now = entry.due
            entry.action()
        }
        now = target
    }
}
