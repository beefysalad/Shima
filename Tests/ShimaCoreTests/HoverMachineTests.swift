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

    @Test func dragEnteredFromCollapsedGrowsAndExpands() {
        let (machine, effects) = run([.dragEntered])
        #expect(machine.phase == .dragHovering)
        #expect(effects == [.cancelTimer, .growPanel, .setHotRegion(.expanded), .animateExpand])
        let (_, duplicate) = run([.dragEntered, .dragEntered])
        #expect(duplicate.isEmpty)
    }

    @Test func dragEnteredDuringPeekCancelsPeek() {
        let inputs: [HoverInput] = [.peekRequested, .dragEntered]
        let (machine, effects) = run(inputs)
        #expect(machine.phase == .dragHovering)
        #expect(effects == [.cancelTimer, .growPanel, .setHotRegion(.expanded), .animateExpand])
        let (after, stale) = run(inputs + [.peekElapsed])
        #expect(after.phase == .dragHovering && stale.isEmpty)
    }

    @Test func dragEnteredDuringDwellingExpands() {
        for prefix: [HoverInput] in [[.pointer(inside: true)], [.peekRequested, .pointer(inside: true)]] {
            let inputs = prefix + [.dragEntered]
            let (machine, effects) = run(inputs)
            #expect(machine.phase == .dragHovering)
            #expect(effects == [.cancelTimer, .growPanel, .setHotRegion(.expanded), .animateExpand])
            let (after, stale) = run(inputs + [.dwellElapsed])
            #expect(after.phase == .dragHovering && stale.isEmpty)
        }
    }

    @Test func dragExitedStartsLeaveDebounce() {
        let (machine, effects) = run([.dragEntered, .dragExited])
        #expect(machine.phase == .leaving && effects == [.startTimer(.leave)])
        let (after, duplicate) = run([.dragEntered, .dragExited, .dragEnded(dropped: false)])
        #expect(after.phase == .leaving && duplicate.isEmpty)
    }

    @Test func dragReenterWithinDebounceStaysOpen() {
        let inputs: [HoverInput] = [.dragEntered, .dragExited, .dragEntered]
        let (machine, effects) = run(inputs)
        #expect(machine.phase == .dragHovering)
        #expect(effects == [.cancelTimer, .setHotRegion(.expanded), .animateExpand])
        let (after, stale) = run(inputs + [.leaveElapsed])
        #expect(after.phase == .dragHovering && stale.isEmpty)
    }

    @Test func staleCollapseFinishedAfterReenterIsIgnored() {
        let inputs: [HoverInput] = [.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .leaveElapsed,
                                    .dragEntered]
        let (entered, expand) = run(inputs)
        #expect(entered.phase == .dragHovering)
        #expect(expand == [.cancelTimer, .setHotRegion(.expanded), .animateExpand])
        for suffix: [HoverInput] in [[], [.dragExited], [.dragExited, .leaveElapsed],
                                     [.dragEnded(dropped: true), .pointer(inside: false), .leaveElapsed, .pointer(inside: true)]] {
            let (before, _) = run(inputs + suffix)
            let (after, stale) = run(inputs + suffix + [.collapseFinished(generation: 1)])
            #expect(after.phase == before.phase && stale.isEmpty)
        }
    }

    @Test func dragEndedDroppedStaysExpanded() {
        let inputs: [HoverInput] = [.dragEntered, .dragEnded(dropped: true)]
        let (machine, effects) = run(inputs)
        #expect(machine.phase == .expanded && effects.isEmpty)
        let (leaving, leave) = run(inputs + [.pointer(inside: false)])
        #expect(leaving.phase == .leaving && leave == [.startTimer(.leave)])
    }

    @Test func dragEndedNotDroppedCollapsesAfterLeaveDebounce() {
        let inputs: [HoverInput] = [.dragEntered, .dragEnded(dropped: false)]
        let (leaving, leave) = run(inputs)
        #expect(leaving.phase == .leaving && leave == [.startTimer(.leave)])
        let (collapsing, collapse) = run(inputs + [.leaveElapsed])
        #expect(collapsing.phase == .collapsing)
        #expect(collapse == [.setHotRegion(.idle), .animateCollapse(generation: 1)])
        let (after, duplicate) = run(inputs + [.dragExited])
        #expect(after.phase == .leaving && duplicate.isEmpty)
    }

    @Test func onlyDragExitedStillCollapses() {
        let (machine, effects) = run([.dragEntered, .dragExited, .leaveElapsed, .collapseFinished(generation: 1)])
        #expect(machine.phase == .collapsed && effects == [.shrinkPanel])
    }

    @Test func onlyDragEndedStillCollapses() {
        let (machine, effects) = run([.dragEntered, .dragEnded(dropped: false), .leaveElapsed, .collapseFinished(generation: 1)])
        #expect(machine.phase == .collapsed && effects == [.shrinkPanel])
    }

    @Test func resetClearsDragState() {
        let inputs: [HoverInput] = [.dragEntered, .reset]
        let (machine, effects) = run(inputs)
        #expect(machine.phase == .collapsed)
        #expect(effects == [.cancelTimer, .snapCollapsed, .setHotRegion(.idle), .shrinkPanel])
        let (dwelling, dwell) = run(inputs + [.pointer(inside: true)])
        #expect(dwelling.phase == .dwelling && dwell == [.startTimer(.dwell)])
        let (after, end) = run(inputs + [.dragEnded(dropped: false)])
        #expect(after.phase == .collapsed && end.isEmpty)
    }

    @Test func pointerEventsDuringDragAreIgnored() {
        let inputs: [HoverInput] = [.dragEntered, .pointer(inside: false), .pointer(inside: true), .pointer(inside: false)]
        let (machine, effects) = run(inputs)
        #expect(machine.phase == .dragHovering && effects.isEmpty)
        let (leaving, leave) = run(inputs + [.dragEnded(dropped: true), .pointer(inside: false)])
        #expect(leaving.phase == .leaving && leave == [.startTimer(.leave)])
        let (expanded, enter) = run(inputs + [.dragExited, .pointer(inside: true)])
        #expect(expanded.phase == .expanded && enter == [.cancelTimer])
    }

    @Test func dragEnteredFromExpandedDoesNotRegrow() {
        let (machine, effects) = run([.pointer(inside: true), .dwellElapsed, .dragEntered])
        #expect(machine.phase == .dragHovering)
        #expect(effects == [.cancelTimer, .setHotRegion(.expanded), .animateExpand])
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

    @Test func geometryChangeWhenCollapsedReappliesIdleFrame() {
        let (m, e) = run([.idleGeometryChanged])
        #expect(m.phase == .collapsed && e == [.shrinkPanel])
    }
    @Test func geometryChangeWhileDwellingSmallReappliesIdleFrame() {
        let (m, e) = run([.pointer(inside: true), .idleGeometryChanged])
        #expect(m.phase == .dwelling && e == [.shrinkPanel])
    }
    @Test func geometryChangeWhileDwellingKeepsTheDwell() {
        let (m, e) = run([.pointer(inside: true), .idleGeometryChanged, .dwellElapsed])
        #expect(m.phase == .expanded && e == [.growPanel, .setHotRegion(.expanded), .animateExpand])
    }
    @Test func geometryChangeWhileExpandedWaits() {
        let (m, e) = run([.pointer(inside: true), .dwellElapsed, .idleGeometryChanged])
        #expect(m.phase == .expanded && e == [])
    }
    @Test func geometryChangeWhileLeavingWaits() {
        let (m, e) = run([.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .idleGeometryChanged])
        #expect(m.phase == .leaving && e == [])
    }
    @Test func geometryChangeWhileCollapsingWaits() {
        let inputs: [HoverInput] = [.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .leaveElapsed, .idleGeometryChanged]
        let (m, e) = run(inputs)
        #expect(m.phase == .collapsing && e == [])
        let (done, finish) = run(inputs + [.collapseFinished(generation: 1)])
        #expect(done.phase == .collapsed && finish == [.shrinkPanel])
    }
    @Test func geometryChangeWhileDwellingLargeWaitsForCollapseFinish() {
        let inputs: [HoverInput] = [.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .leaveElapsed, .pointer(inside: true), .idleGeometryChanged]
        let (m, e) = run(inputs)
        #expect(m.phase == .dwelling && e == [])
        let (_, finish) = run(inputs + [.collapseFinished(generation: 1)])
        #expect(finish == [.shrinkPanel])
        let (grown, grow) = run(inputs + [.collapseFinished(generation: 1), .dwellElapsed])
        #expect(grown.phase == .expanded && grow == [.growPanel, .setHotRegion(.expanded), .animateExpand])
    }
    @Test func staleCollapseFinishAfterGeometryChangeIgnored() {
        let (m, e) = run([.pointer(inside: true), .dwellElapsed, .pointer(inside: false), .leaveElapsed, .pointer(inside: true),
                          .dwellElapsed, .idleGeometryChanged, .collapseFinished(generation: 1)])
        #expect(m.phase == .expanded && e == [])
    }
    @Test func geometryChangeKeepsPointerDedupe() {
        let (m, e) = run([.pointer(inside: true), .idleGeometryChanged, .pointer(inside: true)])
        #expect(m.phase == .dwelling && e == [])
    }

    @Test func peekFromCollapsed() {
        let (machine, effects) = run([.peekRequested])
        #expect(machine.phase == .peeking)
        #expect(effects == [.growPanelForPeek, .setHotRegion(.peek), .animatePeekIn, .startTimer(.peek)])
    }

    @Test func peekIgnoredUnlessCollapsed() {
        let enter: [HoverInput] = [.pointer(inside: true)]
        let expand = enter + [.dwellElapsed]
        let leave = expand + [.pointer(inside: false)]
        for inputs in [enter, expand, leave, leave + [.leaveElapsed]] {
            let (before, _) = run(inputs)
            let (after, effects) = run(inputs + [.peekRequested])
            #expect(after.phase == before.phase && effects.isEmpty)
        }
    }

    @Test func secondPeekRestartsTimer() {
        let (machine, effects) = run([.peekRequested, .peekRequested])
        #expect(machine.phase == .peeking && effects == [.startTimer(.peek)])
    }

    @Test func peekElapsedCollapses() {
        let inputs: [HoverInput] = [.peekRequested, .peekElapsed]
        let (collapsing, collapse) = run(inputs)
        #expect(collapsing.phase == .collapsing)
        #expect(collapse == [.setHotRegion(.idle), .animateCollapse(generation: 1)])
        let (collapsed, shrink) = run(inputs + [.collapseFinished(generation: 1)])
        #expect(collapsed.phase == .collapsed && shrink == [.shrinkPanel])
    }

    @Test func hoverDuringPeekExpandsAndStaleTimerIsIgnored() {
        let inputs: [HoverInput] = [.peekRequested, .pointer(inside: true)]
        let (dwelling, dwell) = run(inputs)
        #expect(dwelling.phase == .dwelling && dwell == [.startTimer(.dwell)])
        let (expanded, expand) = run(inputs + [.dwellElapsed])
        #expect(expanded.phase == .expanded)
        #expect(expand == [.growPanel, .setHotRegion(.expanded), .animateExpand])
        let (afterTimer, effects) = run(inputs + [.dwellElapsed, .peekElapsed])
        #expect(afterTimer.phase == .expanded && effects.isEmpty)
    }

    @Test func peekCollapseCompletionAfterRehover() {
        let inputs: [HoverInput] = [.peekRequested, .peekElapsed, .pointer(inside: true)]
        let (dwelling, shrink) = run(inputs + [.collapseFinished(generation: 1)])
        #expect(dwelling.phase == .dwelling && shrink == [.shrinkPanel])
        let (_, expand) = run(inputs + [.collapseFinished(generation: 1), .dwellElapsed])
        #expect(expand == [.growPanel, .setHotRegion(.expanded), .animateExpand])
        let (afterStale, effects) = run(inputs + [.collapseFinished(generation: 0)])
        #expect(afterStale.phase == .dwelling && effects.isEmpty)
    }

    @Test func pointerOutsideAndGeometryChangeKeepPeek() {
        for input in [HoverInput.pointer(inside: false), .idleGeometryChanged] {
            let (machine, effects) = run([.peekRequested, input])
            #expect(machine.phase == .peeking && effects.isEmpty)
        }
    }

    @Test func leavingDwellFromPeekStartsCollapse() {
        let inputs: [HoverInput] = [.peekRequested, .pointer(inside: true), .pointer(inside: false)]
        let (machine, effects) = run(inputs)
        #expect(machine.phase == .collapsing)
        #expect(effects == [.cancelTimer, .setHotRegion(.idle), .animateCollapse(generation: 1)])
        let (collapsed, shrink) = run(inputs + [.collapseFinished(generation: 1)])
        #expect(collapsed.phase == .collapsed && shrink == [.shrinkPanel])
    }

    @Test func completedCollapseDoesNotShrinkLaterPeekDwell() {
        let inputs: [HoverInput] = [.peekRequested, .peekElapsed, .collapseFinished(generation: 1),
                                    .peekRequested, .pointer(inside: true), .collapseFinished(generation: 1)]
        let (machine, effects) = run(inputs)
        #expect(machine.phase == .dwelling && effects.isEmpty)
    }

    @Test func resetDuringPeek() {
        let (machine, effects) = run([.peekRequested, .reset])
        #expect(machine.phase == .collapsed)
        #expect(effects == [.cancelTimer, .snapCollapsed, .setHotRegion(.idle), .shrinkPanel])
    }
}
