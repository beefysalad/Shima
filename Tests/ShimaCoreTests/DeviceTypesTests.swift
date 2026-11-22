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
        // Name keywords first: the name beats the headphones class for AirPods (spike S1: major 4 minor 6).
        (nil, nil, "AirPods 4", DeviceKind.earbuds),
        (nil, nil, "Galaxy BUDS", .earbuds),
        (4, 6, "AirPods 4 (ANC)", .earbuds),
        // Class of device, `minor` is the 6-bit field IOBluetooth reports.
        (4, 6, "WH-1000XM5", .headphones),
        (4, 1, "Headset", .headphones),
        (4, 2, "Hands-free", .headphones),
        (4, 5, "Speaker", .speaker),
        (5, 16, "Keychron K3", .keyboard),
        (5, 16, "Unknown board", .keyboard),
        (5, 32, "MX Master 3S", .mouse),
        (5, 32, "Unknown pointer", .mouse),
        (5, 48, "Combo remote", .keyboard),
        // Remaining name keywords, then other.
        (nil, nil, "Keychron K3", .keyboard),
        (nil, nil, "MX Master 3S", .mouse),
        (5, 0, "Magic Trackpad", .trackpad),
        (nil, nil, "DualSense", .gamepad),
        (nil, nil, "Mystery device", .other),
        (4, 0, "Mystery device", .other),
        (5, 0, "Mystery device", .other)
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
