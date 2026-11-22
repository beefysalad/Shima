import AppKit
import os
import ShimaCore

@MainActor
final class DeviceService: NSObject {
    private static let logger = Logger(subsystem: "local.shima", category: "device")
    private static let fakeNotification = Notification.Name("local.shima.fake-device")

    private let islandController: IslandPanelController
    private let client: any DeviceClient
    private var policy: DevicePeekPolicy?

    init(islandController: IslandPanelController, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.islandController = islandController
        if environment["SHIMA_FAKE_DEVICES"] == "1" {
            client = FakeDeviceClient()
        } else {
            client = IOBluetoothDeviceClient()
        }
        super.init()
    }

    func start() {
        guard policy == nil else { return }
        client.onConnect = { [weak self] in self?.receive($0) }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        if client is FakeDeviceClient {
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(fakeControl(_:)), name: Self.fakeNotification,
                object: nil, suspensionBehavior: .deliverImmediately)
            Self.logger.info("device mode fake")
        }
        policy = DevicePeekPolicy(startedAt: Date())
        client.start()
    }

    func stop() {
        guard policy != nil else { return }
        policy = nil
        client.onConnect = nil
        client.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.didWakeNotification, object: nil)
        if client is FakeDeviceClient {
            DistributedNotificationCenter.default().removeObserver(self, name: Self.fakeNotification, object: nil)
        }
    }

    @objc nonisolated private func didWake(_ notification: Notification) {
        let now = Date()
        DispatchQueue.main.async { [weak self] in
            self?.policy?.didWake(at: now)
        }
    }

    private func receive(_ event: DeviceEvent) {
        guard let decision = policy?.decide(event, now: Date(), enabled: islandController.state.devicePopupsEnabled) else {
            return
        }

        let result: String
        switch decision {
        case let .show(peek):
            result = islandController.showPeek(.device(peek), duration: peek.duration) ? "shown" : "drop(islandBusy)"
        case let .drop(reason):
            result = "drop(\(reason))"
        }
        Self.logger.info("device connect kind=\(event.kind.rawValue, privacy: .public) -> \(result, privacy: .public) name=\(event.name, privacy: .private)")
    }

    @objc nonisolated private func fakeControl(_ notification: Notification) {
        let command = notification.object as? String ?? ""
        MainActor.assumeIsolated { handleFake(command) }
    }

    private func handleFake(_ command: String) {
        guard let fake = client as? FakeDeviceClient, policy != nil else { return }
        let fields = command.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 4, fields[0] == "connect",
              !fields[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let kind = DeviceKind(rawValue: String(fields[2])) else {
            Self.logger.info("device fake bad command")
            return
        }

        let battery = Int(fields[3])
        guard fields[3] == "-" || battery.map({ (0...100).contains($0) }) == true else {
            Self.logger.info("device fake bad command")
            return
        }

        let name = String(fields[1])
        fake.emit(DeviceEvent(address: name, name: name, kind: kind, batteryPercent: battery))
    }
}
