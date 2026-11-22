@MainActor public final class HoverController {
    private let scheduler: any Scheduler
    private let timing: HoverTiming
    private let perform: @MainActor (HoverEffect) -> Void
    private var machine = HoverMachine()
    private var peekDuration: Duration = .zero
    private var pendingTask: (any ScheduledTask)?
    private var applyingEffects = false
    private var transitions: [(
        from: HoverPhase, to: HoverPhase, effects: [HoverEffect], peekDuration: Duration
    )] = []

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

    @discardableResult public func peek(duration: Duration) -> Bool {
        guard phase == .collapsed || phase == .peeking else { return false }
        peekDuration = duration
        handle(.peekRequested)
        return true
    }

    public func pointer(inside: Bool) {
        handle(.pointer(inside: inside))
    }

    public func collapseFinished(generation: Int) {
        handle(.collapseFinished(generation: generation))
    }

    public func idleGeometryChanged() {
        handle(.idleGeometryChanged)
    }

    public func reset() {
        handle(.reset)
    }

    private func handle(_ input: HoverInput) {
        let from = machine.phase
        let effects = machine.handle(input)
        let to = machine.phase
        guard from != to || !effects.isEmpty else { return }
        transitions.append((from, to, effects, peekDuration))

        // Updating the hot region can report a pointer event synchronously.
        // Apply its effects after the current transition so it can replace the timer.
        guard !applyingEffects else { return }
        applyingEffects = true
        while !transitions.isEmpty {
            let transition = transitions.removeFirst()
            apply(transition.effects, peekDuration: transition.peekDuration)
            if transition.from != transition.to {
                onPhaseChange?(transition.from, transition.to)
            }
        }
        applyingEffects = false
    }

    private func apply(_ effects: [HoverEffect], peekDuration: Duration) {
        for effect in effects {
            switch effect {
            case .startTimer(let timer):
                pendingTask?.cancel()
                let (delay, elapsed): (Duration, HoverInput) = switch timer {
                case .dwell: (timing.dwell, .dwellElapsed)
                case .leave: (timing.leaveDebounce, .leaveElapsed)
                case .peek: (peekDuration, .peekElapsed)
                }
                pendingTask = scheduler.schedule(after: delay) { [weak self] in
                    guard let self else { return }
                    self.pendingTask = nil
                    self.handle(elapsed)
                }
            case .cancelTimer:
                pendingTask?.cancel()
                pendingTask = nil
            default:
                perform(effect)
            }
        }
    }
}
