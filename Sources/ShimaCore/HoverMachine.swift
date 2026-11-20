public enum HoverPhase: Equatable, Sendable {
    case collapsed, dwelling, expanded, leaving, collapsing
}

public enum HoverTimer: Equatable, Sendable {
    case dwell, leave
}

public enum HoverInput: Equatable, Sendable {
    case pointer(inside: Bool)
    case dwellElapsed, leaveElapsed
    case collapseFinished(generation: Int)
    case reset
}

public enum HoverEffect: Equatable, Sendable {
    case startTimer(HoverTimer), cancelTimer
    case growPanel, shrinkPanel, setHotRegion(HotRegion)
    case animateExpand, animateCollapse(generation: Int), snapCollapsed
}

public struct HoverMachine: Sendable {
    public private(set) var phase: HoverPhase = .collapsed
    private var pointerInside = false
    private var panelLarge = false
    private var generation = 0

    public init() {}

    public mutating func handle(_ input: HoverInput) -> [HoverEffect] {
        if case .pointer(let inside) = input {
            guard inside != pointerInside else { return [] }
            pointerInside = inside
        }

        switch (phase, input) {
        case (_, .reset):
            generation += 1
            phase = .collapsed
            pointerInside = false
            var effects: [HoverEffect] = [.cancelTimer, .snapCollapsed, .setHotRegion(.idle)]
            if panelLarge {
                effects.append(.shrinkPanel)
            }
            panelLarge = false
            return effects

        case (.collapsed, .pointer(inside: true)), (.collapsing, .pointer(inside: true)):
            phase = .dwelling
            return [.startTimer(.dwell)]

        case (.dwelling, .pointer(inside: false)):
            phase = panelLarge ? .collapsing : .collapsed
            return [.cancelTimer]

        case (.dwelling, .dwellElapsed):
            phase = .expanded
            var effects: [HoverEffect] = panelLarge ? [] : [.growPanel]
            panelLarge = true
            effects += [.setHotRegion(.expanded), .animateExpand]
            return effects

        case (.expanded, .pointer(inside: false)):
            phase = .leaving
            return [.startTimer(.leave)]

        case (.leaving, .pointer(inside: true)):
            phase = .expanded
            return [.cancelTimer]

        case (.leaving, .leaveElapsed):
            generation += 1
            phase = .collapsing
            return [.setHotRegion(.idle), .animateCollapse(generation: generation)]

        case (.collapsing, .collapseFinished(let completedGeneration)) where completedGeneration == generation:
            phase = .collapsed
            panelLarge = false
            return [.shrinkPanel]

        case (.dwelling, .collapseFinished(let completedGeneration)) where completedGeneration == generation && panelLarge:
            panelLarge = false
            return [.shrinkPanel]

        default:
            return []
        }
    }
}
