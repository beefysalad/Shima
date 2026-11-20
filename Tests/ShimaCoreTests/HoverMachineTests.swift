import Testing
@testable import ShimaCore

@Suite struct HoverMachineTests {
    private func run(_ inputs: [HoverInput]) -> (HoverMachine, [HoverEffect]) {
        var machine = HoverMachine()
        var effects: [HoverEffect] = []
        for input in inputs {
            effects = machine.handle(input)
        }
        return (machine, effects)
    }

    @Test func enterStartsDwell() {
        let (machine, effects) = run([.pointer(inside: true)])
        #expect(machine.phase == .dwelling)
        #expect(effects == [.startTimer(.dwell)])
    }

    @Test func passThroughCancelsDwell() {
        let (machine, effects) = run([.pointer(inside: true), .pointer(inside: false)])
        #expect(machine.phase == .collapsed)
        #expect(effects == [.cancelTimer])
    }

    @Test func dwellExpandsAndGrowsOnce() {
        let (machine, effects) = run([.pointer(inside: true), .dwellElapsed])
        #expect(machine.phase == .expanded)
        #expect(effects == [.growPanel, .setHotRegion(.expanded), .animateExpand])
    }

    @Test func leaveStartsDebounce() {
        let (machine, effects) = run([.pointer(inside: true), .dwellElapsed, .pointer(inside: false)])
        #expect(machine.phase == .leaving)
        #expect(effects == [.startTimer(.leave)])
    }

    @Test func reenterCancelsDebounce() {
        let (machine, effects) = run([.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .pointer(inside: true)])
        #expect(machine.phase == .expanded)
        #expect(effects == [.cancelTimer])
    }

    @Test func debounceCollapses() {
        let (machine, effects) = run([.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .leaveElapsed])
        #expect(machine.phase == .collapsing)
        #expect(effects == [.setHotRegion(.idle), .animateCollapse(generation: 1)])
    }

    @Test func collapseFinishShrinks() {
        let (machine, effects) = run([.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .leaveElapsed, .collapseFinished(generation: 1)])
        #expect(machine.phase == .collapsed)
        #expect(effects == [.shrinkPanel])
    }

    @Test func staleCollapseFinishIgnored() {
        let (machine, effects) = run([.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .leaveElapsed, .collapseFinished(generation: 0)])
        #expect(machine.phase == .collapsing)
        #expect(effects == [])
    }

    @Test func reenterDuringCollapseDwellsThenExpandsWithoutGrow() {
        let inputs: [HoverInput] = [.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .leaveElapsed, .pointer(inside: true)]
        let (dwelling, dwellEffects) = run(inputs)
        let (expanded, expandEffects) = run(inputs + [.dwellElapsed])
        #expect(dwelling.phase == .dwelling && dwellEffects == [.startTimer(.dwell)])
        #expect(expanded.phase == .expanded && expandEffects == [.setHotRegion(.expanded), .animateExpand])
    }

    @Test func lateCollapseCompletionAfterReexpandIsIgnored() {
        let (machine, effects) = run([.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .leaveElapsed, .pointer(inside: true), .dwellElapsed, .collapseFinished(generation: 1)])
        #expect(machine.phase == .expanded)
        #expect(effects == [])
    }

    @Test func collapseFinishWhileDwellingShrinksThenDwellGrows() {
        let inputs: [HoverInput] = [.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .leaveElapsed, .pointer(inside: true), .collapseFinished(generation: 1)]
        let (dwelling, dwellEffects) = run(inputs)
        let (expanded, expandEffects) = run(inputs + [.dwellElapsed])
        #expect(dwelling.phase == .dwelling && dwellEffects == [.shrinkPanel])
        #expect(expanded.phase == .expanded && expandEffects == [.growPanel, .setHotRegion(.expanded), .animateExpand])
    }

    @Test func leavingDwellDuringCollapseReturnsToCollapsing() {
        let (machine, effects) = run([.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .leaveElapsed, .pointer(inside: true), .pointer(inside: false)])
        #expect(machine.phase == .collapsing)
        #expect(effects == [.cancelTimer])
    }

    @Test func duplicatePointerInsideIsIgnored() {
        let (machine, effects) = run([.pointer(inside: true), .pointer(inside: true)])
        #expect(machine.phase == .dwelling)
        #expect(effects == [])
    }

    @Test func staleDwellTimerIgnored() {
        let (machine, effects) = run([.dwellElapsed])
        #expect(machine.phase == .collapsed)
        #expect(effects == [])
    }

    @Test func resetFromExpandedSnapsAndShrinks() {
        let (machine, effects) = run([.pointer(inside: true), .dwellElapsed, .reset])
        #expect(machine.phase == .collapsed)
        #expect(effects == [.cancelTimer, .snapCollapsed, .setHotRegion(.idle), .shrinkPanel])
    }

    @Test func resetWhenCollapsedDoesNotShrink() {
        let (machine, effects) = run([.reset])
        #expect(machine.phase == .collapsed)
        #expect(effects == [.cancelTimer, .snapCollapsed, .setHotRegion(.idle)])
    }
}
