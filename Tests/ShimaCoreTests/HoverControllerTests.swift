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
}
