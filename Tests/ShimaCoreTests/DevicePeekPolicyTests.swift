import Foundation
import Testing
import ShimaCore

@Suite struct DevicePeekPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    /// Started long before `now`, so the launch grace does not apply unless a test asks for it.
    private func makePolicy() -> DevicePeekPolicy { DevicePeekPolicy(startedAt: now.addingTimeInterval(-60)) }

    private func event(_ address: String = "a", name: String = "Mouse", battery: Int? = 82) -> DeviceEvent {
        DeviceEvent(address: address, name: name, kind: .mouse, batteryPercent: battery)
    }

    private func peek(subtitle: String = "Mouse", batteryText: String? = "82%") -> PeekDecision {
        .show(DevicePeek(title: "Connected", subtitle: subtitle, batteryText: batteryText,
                         kind: .mouse, duration: .seconds(3)))
    }

    @Test func displayNameFallbackAndTruncation() {
        var policy = makePolicy()
        #expect(policy.decide(event("a", name: ""), now: now, enabled: true) == peek(subtitle: "Bluetooth device"))
        #expect(policy.decide(event("b", name: " \t\n"), now: now, enabled: true) == peek(subtitle: "Bluetooth device"))
        #expect(policy.decide(event("c", name: " Mouse "), now: now, enabled: true) == peek())
        let longName = String(repeating: "👩🏽‍💻", count: 60)
        #expect(policy.decide(event("d", name: longName), now: now, enabled: true) == peek(subtitle: String(longName.prefix(39)) + "…"))
    }

    @Test(arguments: [(nil, nil), (-1, nil), (101, nil), (0, "0%"), (100, "100%")] as [(Int?, String?)])
    func batteryOutOfRangeIsHidden(battery: Int?, text: String?) {
        var policy = makePolicy()
        #expect(policy.decide(event(battery: battery), now: now, enabled: true) == peek(batteryText: text))
    }

    @Test func disabledDrops() {
        var policy = makePolicy()
        policy.didWake(at: now)
        #expect(policy.decide(event(), now: now, enabled: false) == .drop(.disabled))
        let later = now.addingTimeInterval(10)
        #expect(policy.decide(event(), now: later, enabled: false) == .drop(.disabled))
        #expect(policy.decide(event(), now: later, enabled: true) == peek())
    }

    @Test func launchGraceDropsReplayedDevices() {
        var policy = DevicePeekPolicy(startedAt: now)
        #expect(policy.decide(event(), now: now.addingTimeInterval(2.9), enabled: true) == .drop(.launchGrace))
        #expect(policy.decide(event("b"), now: now.addingTimeInterval(3.1), enabled: true) == peek())
    }

    @Test func disabledBeatsLaunchGrace() {
        var policy = DevicePeekPolicy(startedAt: now)
        #expect(policy.decide(event(), now: now.addingTimeInterval(1), enabled: false) == .drop(.disabled))
    }

    @Test func wakeGraceDropsWithinTenSeconds() {
        var policy = makePolicy()
        policy.didWake(at: now)
        #expect(policy.decide(event(), now: now.addingTimeInterval(9.9), enabled: true) == .drop(.wakeGrace))
        #expect(policy.decide(event(), now: now.addingTimeInterval(10.1), enabled: true) == peek())
    }

    @Test func sameAddressWithinFiveSecondsDrops() {
        var policy = makePolicy()
        #expect(policy.decide(event(), now: now, enabled: true) == peek())
        #expect(policy.decide(event("b"), now: now.addingTimeInterval(4), enabled: true) == peek())
        #expect(policy.decide(event(), now: now.addingTimeInterval(4.9), enabled: true) == .drop(.repeated))
        #expect(policy.decide(event(), now: now.addingTimeInterval(5.1), enabled: true) == peek())
    }

    @Test func wakeGraceTakesPrecedenceOverRepeat() {
        var policy = makePolicy()
        #expect(policy.decide(event(), now: now, enabled: true) == peek())
        policy.didWake(at: now.addingTimeInterval(1))
        #expect(policy.decide(event(), now: now.addingTimeInterval(2), enabled: true) == .drop(.wakeGrace))
    }
}
