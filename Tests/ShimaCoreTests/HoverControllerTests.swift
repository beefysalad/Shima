import Testing
import ShimaCore

@Suite @MainActor struct HoverControllerTests {
    let clock = ManualScheduler()

    private final class Recorder {
        var effects: [HoverEffect] = []
        func count(_ effect: HoverEffect) -> Int { effects.filter { $0 == effect }.count }
    }

    private func make() -> (HoverController, Recorder) {
        let recorder = Recorder()
        let controller = HoverController(scheduler: clock) { recorder.effects.append($0) }
        return (controller, recorder)
    }

    private func expand(_ controller: HoverController) {
        controller.pointer(inside: true)
        clock.advance(by: .milliseconds(80))
    }

    @Test func dwellOf80msExpands() {
        let (controller, recorder) = make()
        controller.pointer(inside: true)
        clock.advance(by: .milliseconds(79))
        #expect(controller.phase == .dwelling)
        #expect(recorder.count(.growPanel) == 0)
        clock.advance(by: .milliseconds(1))
        #expect(controller.phase == .expanded)
        #expect(recorder.effects == [.growPanel, .setHotRegion(.expanded), .animateExpand])
    }

    @Test func passingThroughDoesNotExpand() {
        let (controller, recorder) = make()
        controller.pointer(inside: true)
        clock.advance(by: .milliseconds(40))
        controller.pointer(inside: false)
        clock.advance(by: .seconds(1))
        #expect(controller.phase == .collapsed)
        #expect(recorder.effects == [])
        #expect(clock.pendingCount == 0)
    }

    @Test func collapsesExactly300msAfterLeave() {
        let (controller, recorder) = make()
        expand(controller)
        controller.pointer(inside: false)
        clock.advance(by: .milliseconds(299))
        #expect(controller.phase == .leaving)
        clock.advance(by: .milliseconds(1))
        #expect(controller.phase == .collapsing)
        #expect(Array(recorder.effects.suffix(2)) == [.setHotRegion(.idle), .animateCollapse(generation: 1)])
        controller.collapseFinished(generation: 1)
        #expect(controller.phase == .collapsed)
        #expect(recorder.effects.last == .shrinkPanel)
    }

    @Test func reenterDuringDebounceStaysExpanded() {
        let (controller, recorder) = make()
        expand(controller)
        controller.pointer(inside: false)
        clock.advance(by: .milliseconds(200))
        controller.pointer(inside: true)
        clock.advance(by: .seconds(2))
        #expect(controller.phase == .expanded)
        #expect(!recorder.effects.contains { if case .animateCollapse = $0 { return true }; return false })
    }

    @Test func wiggleAtEdgeNeverLoops() {
        let (controller, recorder) = make()
        expand(controller)
        for _ in 0..<20 {
            controller.pointer(inside: false)
            clock.advance(by: .milliseconds(50))
            controller.pointer(inside: true)
            clock.advance(by: .milliseconds(50))
        }
        #expect(controller.phase == .expanded)
        #expect(recorder.effects.filter { if case .animateCollapse = $0 { return true }; return false }.count == 0)
        #expect(recorder.count(.growPanel) == 1)
    }

    @Test func reenterDuringCollapseReexpandsWithoutRegrow() {
        let (controller, recorder) = make()
        expand(controller)
        controller.pointer(inside: false)
        clock.advance(by: .milliseconds(300))
        controller.pointer(inside: true)
        clock.advance(by: .milliseconds(80))
        #expect(controller.phase == .expanded)
        #expect(recorder.count(.growPanel) == 1)
        controller.collapseFinished(generation: 1)
        #expect(controller.phase == .expanded)
        #expect(recorder.count(.shrinkPanel) == 0)
    }

    @Test func duplicateInsideEventsKeepOneTimer() {
        let (controller, _) = make()
        controller.pointer(inside: true)
        controller.pointer(inside: true)
        controller.pointer(inside: true)
        #expect(clock.pendingCount == 1)
        clock.advance(by: .milliseconds(79))
        #expect(controller.phase == .dwelling)
    }

    @Test func resetDuringCollapseIgnoresLateCompletion() {
        let (controller, recorder) = make()
        expand(controller)
        controller.pointer(inside: false)
        clock.advance(by: .milliseconds(300))
        controller.reset()
        controller.collapseFinished(generation: 1)
        #expect(controller.phase == .collapsed)
        #expect(recorder.count(.shrinkPanel) == 1)
        #expect(clock.pendingCount == 0)
    }

    @Test func idleHasNoPendingTimers() {
        let (controller, _) = make()
        expand(controller)
        controller.pointer(inside: false)
        clock.advance(by: .milliseconds(300))
        controller.collapseFinished(generation: 1)
        #expect(clock.pendingCount == 0)
        #expect(controller.hasPendingTimer == false)
    }

    @Test func phaseChangesAreReported() {
        let (controller, _) = make()
        var changes: [(HoverPhase, HoverPhase)] = []
        controller.onPhaseChange = { changes.append(($0, $1)) }
        controller.pointer(inside: true)
        clock.advance(by: .milliseconds(80))
        #expect(changes.count == 2)
        #expect(changes.map { $0.0 } == [.collapsed, .dwelling])
        #expect(changes.map { $0.1 } == [.dwelling, .expanded])
    }

    @Test func idleGeometryChangeIsForwardedWhenSmall() {
        let (controller, recorder) = make()
        controller.idleGeometryChanged()
        #expect(recorder.effects == [.shrinkPanel] && clock.pendingCount == 0)
    }
    @Test func liveToggleWhileDwellingKeepsOneTimer() {
        let (controller, recorder) = make()
        controller.pointer(inside: true)
        clock.advance(by: .milliseconds(40))
        controller.idleGeometryChanged()
        #expect(clock.pendingCount == 1)
        clock.advance(by: .milliseconds(40))
        #expect(controller.phase == .expanded && recorder.count(.growPanel) == 1)
    }

    @Test func peekReturnsTrueAndSchedulesDuration() {
        let (controller, recorder) = make()
        #expect(controller.peek(duration: .seconds(3)))
        #expect(controller.phase == .peeking && clock.pendingCount == 1)
        clock.advance(by: .milliseconds(2999))
        #expect(controller.phase == .peeking)
        clock.advance(by: .milliseconds(1))
        #expect(controller.phase == .collapsing)
        #expect(recorder.effects == [.growPanelForPeek, .setHotRegion(.peek), .animatePeekIn,
                                     .setHotRegion(.idle), .animateCollapse(generation: 1)])
    }

    @Test func peekReturnsFalseWhenHovering() {
        let (controller, _) = make()
        expand(controller)
        #expect(!controller.peek(duration: .seconds(3)))
        #expect(controller.phase == .expanded && clock.pendingCount == 0)
    }

    @Test func hoverCancelsPeekTimer() {
        let (controller, recorder) = make()
        controller.peek(duration: .seconds(3))
        controller.pointer(inside: true)
        #expect(controller.phase == .dwelling && clock.pendingCount == 1)
        clock.advance(by: .milliseconds(79))
        #expect(controller.phase == .dwelling)
        clock.advance(by: .milliseconds(1))
        #expect(controller.phase == .expanded && clock.pendingCount == 0)
        clock.advance(by: .seconds(3))
        #expect(controller.phase == .expanded && recorder.effects.last == .animateExpand)
    }

    @Test func peekTimerGoneAfterCollapse() {
        let (controller, _) = make()
        controller.peek(duration: .seconds(3))
        clock.advance(by: .seconds(3))
        controller.collapseFinished(generation: 1)
        #expect(controller.phase == .collapsed)
        #expect(!controller.hasPendingTimer && clock.pendingCount == 0)
    }

    @Test func replacementPeekUsesLatestDuration() {
        let (controller, recorder) = make()
        controller.peek(duration: .seconds(3))
        clock.advance(by: .seconds(2))
        #expect(controller.peek(duration: .seconds(4)))
        #expect(controller.phase == .peeking && clock.pendingCount == 1)
        clock.advance(by: .milliseconds(3999))
        #expect(controller.phase == .peeking)
        #expect(recorder.count(.growPanelForPeek) == 1 && recorder.count(.animatePeekIn) == 1)
        clock.advance(by: .milliseconds(1))
        #expect(controller.phase == .collapsing && clock.pendingCount == 0)
    }

    @Test func resetCancelsPeekTimer() {
        let (controller, recorder) = make()
        controller.peek(duration: .seconds(3))
        controller.reset()
        clock.advance(by: .seconds(3))
        #expect(controller.phase == .collapsed && !controller.hasPendingTimer)
        #expect(recorder.effects.last == .shrinkPanel && clock.pendingCount == 0)
    }

    @Test func pointerReportedSynchronouslyByPeekHotRegionStartsDwell() {
        let recorder = Recorder()
        var changes: [HoverPhase] = []
        weak var activeController: HoverController?
        let controller = HoverController(scheduler: clock) { effect in
            recorder.effects.append(effect)
            if effect == .setHotRegion(.peek) {
                activeController?.pointer(inside: true)
            }
        }
        activeController = controller
        controller.onPhaseChange = { _, to in changes.append(to) }
        #expect(controller.peek(duration: .seconds(3)))
        #expect(controller.phase == .dwelling && clock.pendingCount == 1)
        clock.advance(by: .milliseconds(80))
        #expect(controller.phase == .expanded && clock.pendingCount == 0)
        #expect(changes == [.peeking, .dwelling, .expanded])
        #expect(recorder.effects.last == .animateExpand)
    }
}
