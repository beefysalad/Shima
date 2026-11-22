import Testing
@testable import ShimaCore

@Suite struct SpotifyRequestGateTests {
    typealias T = SpotifyRequestGate.Ticket
    typealias O = SpotifyRequestGate.Outcome

    @Test func firstRequestStarts() {
        var g = SpotifyRequestGate()
        #expect(g.request(pid: 7) == T(seq: 1, pid: 7) && g.inFlight)
    }
    @Test func finishWithoutDirtyHasNoFollowUp() {
        var g = SpotifyRequestGate(); let t = g.request(pid: 7)!
        #expect(g.finish(t, currentPid: 7) == O(apply: true, next: nil) && !g.inFlight)
    }
    @Test func requestsWhileInFlightCoalesceIntoOneFollowUp() {
        var g = SpotifyRequestGate(); let t1 = g.request(pid: 7)!
        for _ in 0..<5 { #expect(g.request(pid: 7) == nil) }
        let o = g.finish(t1, currentPid: 7)
        #expect(o == O(apply: true, next: T(seq: 2, pid: 7)))
        #expect(g.finish(o.next!, currentPid: 7) == O(apply: true, next: nil))
    }
    @Test func resultFromOldPidIsDropped() {
        var g = SpotifyRequestGate(); let t = g.request(pid: 7)!
        #expect(g.finish(t, currentPid: 9) == O(apply: false, next: nil))
    }
    @Test func resultAfterInvalidateIsDropped() {
        var g = SpotifyRequestGate(); let t = g.request(pid: 7)!
        g.invalidate()
        #expect(g.finish(t, currentPid: 7).apply == false)
    }
    @Test func invalidateClearsTheOwedFollowUp() {
        var g = SpotifyRequestGate(); let t = g.request(pid: 7)!
        _ = g.request(pid: 7); g.invalidate()
        #expect(g.finish(t, currentPid: 7) == O(apply: false, next: nil))
    }
    @Test func notRunningAtFinishGivesNoFollowUp() {
        var g = SpotifyRequestGate(); let t = g.request(pid: 7)!
        _ = g.request(pid: 7)
        #expect(g.finish(t, currentPid: nil) == O(apply: false, next: nil))
    }
    @Test func commandTicketsAreNeverCoalesced() {
        var g = SpotifyRequestGate(); _ = g.request(pid: 7)
        let c1 = g.ticket(pid: 7), c2 = g.ticket(pid: 7)
        #expect(c1 == T(seq: 2, pid: 7) && c2 == T(seq: 3, pid: 7))
        #expect(g.finish(c1, currentPid: 7) == O(apply: true, next: nil) && g.inFlight)
    }
    @Test func scriptErrorCodes() {
        #expect(SpotifyScriptError(code: -600) == .notRunning(code: -600))
        #expect(SpotifyScriptError(code: -609) == .notRunning(code: -609))
        #expect(SpotifyScriptError(code: -1743) == .permissionDenied)
        #expect(SpotifyScriptError(code: -1712) == .timeout)
        #expect(SpotifyScriptError(code: -10000) == .other(code: -10000))
    }

    @Test func commandWithoutSnapshotDoesNotStartOrDirtySnapshot() {
        var g = SpotifyRequestGate()
        let command = g.ticket(pid: 7)
        #expect(!g.inFlight)
        #expect(g.finish(command, currentPid: 7) == O(apply: true, next: nil))
        #expect(g.request(pid: 7) == T(seq: 2, pid: 7))
    }

    @Test func commandFinishPreservesOwedSnapshot() {
        var g = SpotifyRequestGate()
        let snapshot = g.request(pid: 7)!
        _ = g.request(pid: 7)
        let command = g.ticket(pid: 7)
        #expect(g.finish(command, currentPid: 7) == O(apply: true, next: nil))
        #expect(g.inFlight)
        #expect(g.finish(snapshot, currentPid: 7) == O(apply: true, next: T(seq: 3, pid: 7)))
    }

    @Test func invalidateDropsCommandsButAllowsNewCommandsForSamePid() {
        var g = SpotifyRequestGate()
        let old = g.ticket(pid: 7)
        g.invalidate()
        let new = g.ticket(pid: 7)
        #expect(g.finish(old, currentPid: 7) == O(apply: false, next: nil))
        #expect(g.finish(new, currentPid: 7) == O(apply: true, next: nil))
        #expect(!g.inFlight)
    }

    @Test func commandFromOldPidOrAbsentProcessIsDropped() {
        var g = SpotifyRequestGate()
        let command = g.ticket(pid: 7)
        #expect(g.finish(command, currentPid: 9) == O(apply: false, next: nil))
        #expect(g.finish(command, currentPid: nil) == O(apply: false, next: nil))
    }

    @Test func invalidateRetainsInFlightUntilItsCompletion() {
        var g = SpotifyRequestGate()
        let snapshot = g.request(pid: 7)!
        g.invalidate()
        #expect(g.inFlight)
        #expect(g.finish(snapshot, currentPid: nil) == O(apply: false, next: nil))
        #expect(!g.inFlight)
        #expect(g.request(pid: 9) == T(seq: 2, pid: 9))
    }

    @Test func relaunchRequestWhileStaleSnapshotRunsUsesCurrentPid() {
        var g = SpotifyRequestGate()
        let old = g.request(pid: 7)!
        g.invalidate()
        #expect(g.request(pid: 9) == nil)
        let outcome = g.finish(old, currentPid: 9)
        #expect(outcome == O(apply: false, next: T(seq: 2, pid: 9)))
        #expect(g.inFlight)
        #expect(g.finish(outcome.next!, currentPid: 9) == O(apply: true, next: nil))
        #expect(!g.inFlight)
    }

    @Test func dirtySnapshotFollowsCurrentPidWithoutInvalidation() {
        var g = SpotifyRequestGate()
        let old = g.request(pid: 7)!
        _ = g.request(pid: 9)
        #expect(g.finish(old, currentPid: 9) == O(apply: false, next: T(seq: 2, pid: 9)))
    }

    @Test func oldCompletionCannotConsumeNewSnapshotsDirtyFlag() {
        var g = SpotifyRequestGate()
        let old = g.request(pid: 7)!
        g.invalidate()
        _ = g.finish(old, currentPid: nil)
        let new = g.request(pid: 9)!
        _ = g.request(pid: 9)
        #expect(g.finish(old, currentPid: 9) == O(apply: false, next: nil))
        #expect(g.inFlight)
        #expect(g.finish(new, currentPid: 9) == O(apply: true, next: T(seq: 3, pid: 9)))
    }

    @Test func repeatedInvalidationStalesOnlyTicketsIssuedSoFar() {
        var g = SpotifyRequestGate()
        g.invalidate()
        let first = g.ticket(pid: 7)
        g.invalidate()
        let second = g.ticket(pid: 7)
        g.invalidate()
        let third = g.ticket(pid: 7)
        #expect(g.finish(first, currentPid: 7).apply == false)
        #expect(g.finish(second, currentPid: 7).apply == false)
        #expect(g.finish(third, currentPid: 7).apply == true)
    }

    @Test func absentProcessFinishClearsDirtyForNextRequest() {
        var g = SpotifyRequestGate()
        let old = g.request(pid: 7)!
        _ = g.request(pid: 7)
        _ = g.finish(old, currentPid: nil)
        let new = g.request(pid: 9)!
        #expect(g.finish(new, currentPid: 9) == O(apply: true, next: nil))
    }

    @Test func sameTrackIDBothTimesIsConsistent() {
        #expect(SpotifySnapshotConsistency.isConsistent(firstTrackID: "a", lastTrackID: "a"))
        #expect(SpotifySnapshotConsistency.isConsistent(firstTrackID: nil, lastTrackID: nil))
    }
    @Test func differingTrackIDsAreInconsistent() {
        #expect(!SpotifySnapshotConsistency.isConsistent(firstTrackID: "a", lastTrackID: "b"))
        #expect(!SpotifySnapshotConsistency.isConsistent(firstTrackID: "a", lastTrackID: nil))
    }
    @Test func consistentSnapshotIsAppliedWithoutRetry() {
        var g = SpotifyRequestGate(); let t = g.request(pid: 7)!
        #expect(g.finish(t, currentPid: 7, consistent: true) == O(apply: true, next: nil))
    }
    @Test func inconsistentSnapshotIsDiscardedAndReReadOnce() {
        var g = SpotifyRequestGate(); let t = g.request(pid: 7)!
        let o = g.finish(t, currentPid: 7, consistent: false)
        #expect(o == O(apply: false, next: T(seq: 2, pid: 7)) && g.inFlight)
        #expect(g.finish(o.next!, currentPid: 7, consistent: true) == O(apply: true, next: nil))
    }
    @Test func secondInconsistentSnapshotInARowDoesNotLoop() {
        var g = SpotifyRequestGate(); let t = g.request(pid: 7)!
        let o = g.finish(t, currentPid: 7, consistent: false)
        let o2 = g.finish(o.next!, currentPid: 7, consistent: false)
        #expect(o2 == O(apply: false, next: nil) && !g.inFlight)
    }
    @Test func retryAllowanceResetsAfterAConsistentSnapshot() {
        var g = SpotifyRequestGate(); let t = g.request(pid: 7)!
        let o = g.finish(t, currentPid: 7, consistent: false)
        _ = g.finish(o.next!, currentPid: 7, consistent: true)
        let t2 = g.request(pid: 7)!
        #expect(g.finish(t2, currentPid: 7, consistent: false).next != nil)
    }
    @Test func inconsistentSnapshotAfterQuitOrInvalidateIsNotReRead() {
        var g = SpotifyRequestGate(); let t = g.request(pid: 7)!
        #expect(g.finish(t, currentPid: nil, consistent: false) == O(apply: false, next: nil))
        var h = SpotifyRequestGate(); let u = h.request(pid: 7)!
        h.invalidate()
        #expect(h.finish(u, currentPid: 7, consistent: false) == O(apply: false, next: nil))
    }
}
