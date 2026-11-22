import Testing
import ShimaCore

@Suite struct DeviceTypesTests {
    @Test func symbolNames() {
        #expect(DeviceKind.allCases.map(\.symbolName) == [
            "headphones", "airpods.gen3", "keyboard", "computermouse",
            "rectangle.and.hand.point.up.left", "hifispeaker", "gamecontroller", "wave.3.right"
        ])
    }

    @Test(arguments: [
        (nil, nil, "AirPods 4", DeviceKind.earbuds),
        (nil, nil, "Galaxy BUDS", .earbuds),
        (nil, nil, "Keychron K3", .keyboard),
        (nil, nil, "MX Master 3S", .mouse),
        (nil, nil, "Magic Trackpad", .trackpad),
        (nil, nil, "DualSense", .gamepad),
        (nil, nil, "Mystery device", .other),
        (4, 1, "AirPods 4", .headphones),
        (4, 2, "Keyboard", .headphones),
        (4, 6, "Speaker", .headphones),
        (4, 5, "AirPods 4", .speaker),
        (4, 0, "AirPods 4", .earbuds),
        (5, 0x40, "AirPods 4", .keyboard),
        (5, 0x80, "Magic Trackpad", .mouse),
        (5, 0xC1, "Mouse", .keyboard)
    ] as [(Int?, Int?, String, DeviceKind)])
    func classification(major: Int?, minor: Int?, name: String, expected: DeviceKind) {
        #expect(DeviceKind.classify(major: major, minor: minor, name: name) == expected)
    }

    @Test @MainActor func fakeClientTracksLifecycleAndEmitsConnections() {
        let client = FakeDeviceClient()
        let event = DeviceEvent(address: "a", name: "Mouse", kind: .mouse, batteryPercent: 60)
        var received: [DeviceEvent] = []
        client.onConnect = { received.append($0) }
        client.start()
        client.emit(event)
        client.stop()
        #expect(client.startCount == 1 && client.stopCount == 1)
        #expect(received == [event])
    }
}
