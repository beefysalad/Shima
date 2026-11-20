import ShimaCore

/// One-shot, cancellable scheduler built on `Task.sleep`. The only scheduled work in the app.
@MainActor final class DispatchScheduler: Scheduler {
    @MainActor final class SleepTask: ScheduledTask {
        var task: Task<Void, Never>?
        func cancel() { task?.cancel() }
    }

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let handle = SleepTask()
        handle.task = Task { @MainActor in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
        return handle
    }
}
