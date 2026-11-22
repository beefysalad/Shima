import Foundation
import Testing
@testable import ShimaCore

@Suite struct ArtworkRequestGateTests {
    private let url = URL(string: "https://example.com/art")!

    @Test func duplicateIdentityKeepsCurrentWork() {
        var gate = ArtworkRequestGate()
        guard case let .load(ticket) = gate.select(trackID: "a", url: url) else { Issue.record("No load"); return }
        #expect(gate.select(trackID: "a", url: url) == .unchanged)
        #expect(gate.accepts(ticket))
    }

    @Test func sameURLForAnotherTrackInvalidatesOldResult() {
        var gate = ArtworkRequestGate()
        guard case let .load(old) = gate.select(trackID: "a", url: url) else { Issue.record("No load"); return }
        _ = gate.select(trackID: "b", url: url)
        #expect(!gate.accepts(old))
    }

    @Test func returningToSameTrackAndURLDropsOldGeneration() {
        var gate = ArtworkRequestGate()
        guard case let .load(old) = gate.select(trackID: "a", url: url) else { Issue.record("No load"); return }
        _ = gate.select(trackID: "b", url: url)
        _ = gate.select(trackID: "a", url: url)
        #expect(!gate.accepts(old))
    }

    @Test func clearingDropsInFlightResult() {
        var gate = ArtworkRequestGate()
        guard case let .load(old) = gate.select(trackID: "a", url: url) else { Issue.record("No load"); return }
        #expect(gate.select(trackID: nil, url: nil) == .clear)
        #expect(!gate.accepts(old))
    }

    @Test func failureSuppressesURLChangesUntilNextTrack() {
        var gate = ArtworkRequestGate()
        guard case let .load(ticket) = gate.select(trackID: "a", url: url) else { Issue.record("No load"); return }
        gate.failed(ticket)
        _ = gate.select(trackID: "a", url: nil)
        #expect(gate.select(trackID: "a", url: URL(string: "https://example.com/new")!) == .clear)
        guard case .load = gate.select(trackID: "b", url: url) else { Issue.record("Next track should retry"); return }
        guard case .load = gate.select(trackID: "a", url: url) else { Issue.record("Returning track should retry"); return }
    }

    @Test func staleFailureCannotSuppressCurrentTrack() {
        var gate = ArtworkRequestGate()
        guard case let .load(old) = gate.select(trackID: "a", url: url) else { Issue.record("No load"); return }
        _ = gate.select(trackID: "b", url: url)
        gate.failed(old)
        guard case .load = gate.select(trackID: "a", url: url) else { Issue.record("Stale failure blocked request"); return }
    }

    @Test func onlyHTTPSWithHostIsAccepted() {
        for value in ["http://example.com/art", "file:///art", "https:art", "https:///art"] {
            var gate = ArtworkRequestGate()
            #expect(gate.select(trackID: "a", url: URL(string: value)!) == .clear)
        }
    }
}
