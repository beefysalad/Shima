@MainActor public final class HoverController {
    private let scheduler: any Scheduler
    private let timing: HoverTiming
    private let perform: @MainActor (HoverEffect) -> Void
    private var machine = HoverMachine()
    private var pendingTask: (any ScheduledTask)?

    public init(
        scheduler: any Scheduler,
        timing: HoverTiming = .standard,
        perform: @escaping @MainActor (HoverEffect) -> Void
    ) {
        self.scheduler = scheduler
        self.timing = timing
        self.perform = perform
    }

    public var phase: HoverPhase { machine.phase }
    public var hasPendingTimer: Bool { pendingTask != nil }
    public var onPhaseChange: (@MainActor (_ from: HoverPhase, _ to: HoverPhase) -> Void)?

    public func pointer(inside: Bool) {
        handle(.pointer(inside: inside))
    }

    public func collapseFinished(generation: Int) {
        handle(.collapseFinished(generation: generation))
    }

    public func reset() {
        handle(.reset)
    }

    private func handle(_ input: HoverInput) {
        let from = machine.phase
        let effects = machine.handle(input)
        let to = machine.phase
        for effect in effects {
            switch effect {
            case .startTimer(let timer):
                pendingTask?.cancel()
                let delay = timer == .dwell ? timing.dwell : timing.leaveDebounce
                pendingTask = scheduler.schedule(after: delay) { [weak self] in
                    guard let self else { return }
                    self.pendingTask = nil
                    self.handle(timer == .dwell ? .dwellElapsed : .leaveElapsed)
                }
            case .cancelTimer:
                pendingTask?.cancel()
                pendingTask = nil
            default:
                perform(effect)
            }
        }
        if from != to {
            onPhaseChange?(from, to)
        }
    }
}
