public enum HoverPhase: Equatable, Sendable {
    case collapsed, peeking, dwelling, expanded, leaving, collapsing, dragHovering
}

public enum HoverTimer: Equatable, Sendable {
    case dwell, leave, peek
}

public enum HoverInput: Equatable, Sendable {
    case pointer(inside: Bool)
    case dwellElapsed, leaveElapsed
    case collapseFinished(generation: Int)
    case peekRequested, peekElapsed
    case dragEntered, dragExited, dragEnded(dropped: Bool)
    case reset
    case idleGeometryChanged
}

public enum HoverEffect: Equatable, Sendable {
    case startTimer(HoverTimer), cancelTimer
    case growPanel, growPanelForPeek, shrinkPanel, setHotRegion(HotRegion)
    case animateExpand, animatePeekIn, animateCollapse(generation: Int), snapCollapsed
}

public struct HoverMachine: Sendable {
    public private(set) var phase: HoverPhase = .collapsed
    private var pointerInside = false
    private var panelLarge = false
    private var panelIsPeekSized = false
    private var generation = 0
    private var collapseInFlight = false
    private var dragActive = false

    public init() {}

    public mutating func handle(_ input: HoverInput) -> [HoverEffect] {
        if case .pointer(let inside) = input {
            guard !dragActive else { return [] }
            guard inside != pointerInside else { return [] }
            pointerInside = inside
        }

        switch (phase, input) {
        case (_, .reset):
            generation += 1
            collapseInFlight = false
            dragActive = false
            phase = .collapsed
            pointerInside = false
            var effects: [HoverEffect] = [.cancelTimer, .snapCollapsed, .setHotRegion(.idle)]
            if panelLarge {
                effects.append(.shrinkPanel)
            }
            panelLarge = false
            panelIsPeekSized = false
            return effects

        case (_, .idleGeometryChanged):
            return panelLarge ? [] : [.shrinkPanel]

        case (_, .dragEntered):
            guard !dragActive else { return [] }
            phase = .dragHovering
            dragActive = true
            pointerInside = true
            // Like completing dwell, re-expanding invalidates the in-flight collapse.
            collapseInFlight = false
            var effects: [HoverEffect] = [.cancelTimer]
            if !panelLarge || panelIsPeekSized { effects.append(.growPanel) }
            panelLarge = true
            panelIsPeekSized = false
            return effects + [.setHotRegion(.expanded), .animateExpand]

        case (.dragHovering, .dragExited), (.dragHovering, .dragEnded(dropped: false)):
            dragActive = false
            pointerInside = false
            phase = .leaving
            return [.startTimer(.leave)]

        case (.dragHovering, .dragEnded(dropped: true)):
            dragActive = false
            pointerInside = true
            phase = .expanded
            return []

        case (.collapsed, .peekRequested):
            phase = .peeking
            panelLarge = true
            panelIsPeekSized = true
            return [.growPanelForPeek, .setHotRegion(.peek), .animatePeekIn, .startTimer(.peek)]

        case (.peeking, .peekRequested):
            return [.startTimer(.peek)]

        case (.collapsed, .pointer(inside: true)), (.collapsing, .pointer(inside: true)),
             (.peeking, .pointer(inside: true)):
            phase = .dwelling
            return [.startTimer(.dwell)]

        case (.dwelling, .pointer(inside: false)) where panelIsPeekSized && !collapseInFlight:
            // A brief pass over a peek replaced its timer with a dwell that is now cancelled.
            return [.cancelTimer] + beginCollapse()

        case (.dwelling, .pointer(inside: false)):
            phase = panelLarge ? .collapsing : .collapsed
            return [.cancelTimer]

        case (.dwelling, .dwellElapsed):
            phase = .expanded
            var effects: [HoverEffect] = !panelLarge || panelIsPeekSized ? [.growPanel] : []
            panelLarge = true
            panelIsPeekSized = false
            collapseInFlight = false
            effects += [.setHotRegion(.expanded), .animateExpand]
            return effects

        case (.expanded, .pointer(inside: false)):
            phase = .leaving
            return [.startTimer(.leave)]

        case (.leaving, .pointer(inside: true)):
            phase = .expanded
            return [.cancelTimer]

        case (.leaving, .leaveElapsed), (.peeking, .peekElapsed):
            return beginCollapse()

        case (.collapsing, .collapseFinished(let completedGeneration)),
             (.dwelling, .collapseFinished(let completedGeneration)):
            guard collapseInFlight, completedGeneration == generation else { return [] }
            if phase == .collapsing { phase = .collapsed }
            collapseInFlight = false
            panelLarge = false
            panelIsPeekSized = false
            return [.shrinkPanel]

        default:
            return []
        }
    }

    private mutating func beginCollapse() -> [HoverEffect] {
        generation += 1
        collapseInFlight = true
        phase = .collapsing
        return [.setHotRegion(.idle), .animateCollapse(generation: generation)]
    }
}
