import AppKit
import CoreGraphics
import Observation
import ShimaCore

/// Notification-driven lifecycle glue. No view owns or starts the capture session.
@Observable @MainActor final class CameraService: NSObject {
    let coordinator: CameraCoordinator
    let capture: CameraCaptureClient?
    let fake: FakeCameraClient?
    var mirrored = true
    private var awake: Bool
    private var systemAwake = true
    private var locked: Bool

    init(state: AppState, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let fakeMode = environment["SHIMA_FAKE_CAMERA"] == "1"
        let client: any CameraClient
        if fakeMode {
            let fixture = FakeCameraClient(permission: .authorized)
            fake = fixture
            capture = nil
            client = fixture
        } else {
            let real = CameraCaptureClient()
            fake = nil
            capture = real
            client = real
        }
        fake?.onRunningChange = { running in
            Log.camera.info("camera fake session \(running ? "start" : "stop", privacy: .public)")
        }
        fake?.onPermissionRequest = { Log.camera.info("camera fake permission requested") }
        coordinator = CameraCoordinator(client: client)
        awake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        locked = (session?["CGSSessionScreenIsLocked"] as? Bool) == true
        super.init()
        state.onCameraContextChange = { [weak self] mode, tab in
            self?.update(mode: mode, tab: tab)
        }
        self.state = state
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(slept), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(woke), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemSlept), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemWoke), name: NSWorkspace.didWakeNotification, object: nil)
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)
        if fakeMode {
            distributed.addObserver(self, selector: #selector(fakeControl(_:)), name: .init("local.shima.fake-camera"), object: nil, suspensionBehavior: .deliverImmediately)
        }
        update()
    }

    @ObservationIgnored private weak var state: AppState?

    private func update(mode: IslandMode? = nil, tab: IslandTab? = nil) {
        guard let state else { return }
        coordinator.setContext(mode: mode ?? state.mode, tab: tab ?? state.selectedTab, screenAvailable: awake && systemAwake && !locked)
    }

    @objc private func slept() { awake = false; update() }
    @objc private func woke() { awake = true; coordinator.refreshPermission(); update() }
    @objc private func systemSlept() { systemAwake = false; update() }
    @objc private func systemWoke() { systemAwake = true; update() }
    @objc private func screenLocked() { locked = true; update() }
    @objc private func screenUnlocked() { locked = false; coordinator.refreshPermission(); update() }

    func shutdown() {
        coordinator.shutdown()
        capture?.stopAndWait()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc nonisolated private func fakeControl(_ note: Notification) {
        let command = note.object as? String ?? ""
        MainActor.assumeIsolated {
            guard let fake else { return }
            Log.camera.info("camera fake \(command, privacy: .public)")
            switch command {
            case "lock": screenLocked()
            case "unlock": screenUnlocked()
            case "sleep": slept()
            case "wake": woke()
            case "system-sleep": systemSlept()
            case "system-wake": systemWoke()
            case "denied": fake.permission = .denied; coordinator.refreshPermission()
            case "allowed": fake.permission = .authorized; coordinator.refreshPermission()
            case "permission-pending": fake.permission = .notDetermined; fake.requestResult = nil; coordinator.refreshPermission()
            case "grant": fake.completePermission(.authorized)
            case "deny": fake.completePermission(.denied)
            default: break
            }
        }
    }
}
