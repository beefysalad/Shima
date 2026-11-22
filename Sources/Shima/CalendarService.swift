import AppKit
import CoreGraphics
import Observation
import ShimaCore

/// Keeps EventKit work gated on the selected tab and screen availability.
@Observable @MainActor final class CalendarService: NSObject {
    let coordinator: CalendarCoordinator
    private let client: EventKitCalendarClient
    @ObservationIgnored private weak var state: AppState?
    @ObservationIgnored private var tabContextObserver: UUID?
    private var screenAwake: Bool
    private var systemAwake = true
    private var locked: Bool
    private var sessionActive: Bool

    init(state: AppState, environment _: [String: String]) {
        let client = EventKitCalendarClient()
        self.client = client
        coordinator = CalendarCoordinator(client: client, calendar: .autoupdatingCurrent, now: { Date() })
        self.state = state
        screenAwake = CGDisplayIsAsleep(CGMainDisplayID()) == 0
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        locked = (session?["CGSSessionScreenIsLocked"] as? Bool) == true
        sessionActive = (session?[kCGSessionOnConsoleKey as String] as? Bool) ?? true
        super.init()

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screenSlept), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenWoke), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemSlept), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemWoke), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionBecameActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)

        tabContextObserver = state.addTabContextObserver { [weak self] mode, tab in
            self?.setContext(mode: mode, tab: tab)
        }
    }

    func shutdown() {
        if let tabContextObserver {
            state?.removeTabContextObserver(tabContextObserver)
            self.tabContextObserver = nil
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        coordinator.shutdown()
        client.shutdown()
    }

    private func setContext(mode: IslandMode, tab: IslandTab) {
        coordinator.setContext(mode: mode, tab: tab,
                               screenAvailable: screenAwake && systemAwake && !locked && sessionActive)
    }

    private func updateContext() {
        guard let state else { return }
        setContext(mode: state.mode, tab: state.selectedTab)
    }

    @objc private func screenSlept() { screenAwake = false; updateContext() }
    @objc private func screenWoke() { screenAwake = true; updateContext() }
    @objc private func systemSlept() { systemAwake = false; updateContext() }
    @objc private func systemWoke() { systemAwake = true; updateContext() }
    @objc private func screenLocked() { locked = true; updateContext() }
    @objc private func screenUnlocked() { locked = false; updateContext() }
    @objc private func sessionResigned() { sessionActive = false; updateContext() }
    @objc private func sessionBecameActive() { sessionActive = true; updateContext() }
    @objc private func appBecameActive() { coordinator.refreshAccess() }
}
