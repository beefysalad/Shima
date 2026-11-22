import Foundation
import IOBluetooth
import ShimaCore

@MainActor
final class IOBluetoothDeviceClient: NSObject, DeviceClient {
    var onConnect: (@MainActor (DeviceEvent) -> Void)?

    private var registration: IOBluetoothUserNotification?

    func start() {
        guard registration == nil else { return }
        registration = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(didConnect(_:device:)))
    }

    func stop() {
        registration?.unregister()
        registration = nil
    }

    @objc nonisolated private func didConnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard device.isConnected(), let address = device.addressString else { return }
        let name = device.name ?? address
        let kind = DeviceKind.classify(major: Int(device.deviceClassMajor), minor: Int(device.deviceClassMinor), name: name)
        let event = DeviceEvent(address: address, name: name, kind: kind, batteryPercent: Self.batteryPercent(of: device))
        let registrationID = ObjectIdentifier(notification)
        DispatchQueue.main.async { [weak self] in
            guard let self, let registration = self.registration,
                  ObjectIdentifier(registration) == registrationID else { return }
            self.onConnect?(event)
        }
    }

    nonisolated private static func batteryPercent(of device: IOBluetoothDevice) -> Int? {
        func percent(_ key: String) -> Int? {
            guard device.responds(to: NSSelectorFromString(key)),
                  let value = device.value(forKey: key) as? Int,
                  (1...100).contains(value) else { return nil }
            return value
        }

        let earbuds = [percent("batteryPercentLeft"), percent("batteryPercentRight")].compactMap { $0 }
        return earbuds.min() ?? percent("batteryPercentSingle") ?? percent("batteryPercentCombined")
    }
}
