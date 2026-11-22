import AppKit
import ShimaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let islandController = IslandPanelController()
    private lazy var spotify = SpotifyService(state: islandController.state, media: islandController.media)
    private var statusItem: NSStatusItem?
    private var loginRegistrationFailed = false
    private let loginItemMenuItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLoginItem), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        showPanel()
        spotify.onLiveChange = { [weak self] in self?.islandController.setLive($0) }
        islandController.onIslandOpened = { [weak self] in self?.spotify.islandOpened() }
        islandController.onCommand = { [weak self] in self?.spotify.perform($0) }
        spotify.start()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func appBecameActive() { Log.focus.error("app became active") }

    @objc private func screensChanged() { showPanel() }

    private func showPanel() {
        islandController.place(on: ScreenLocator.target())
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "shima")
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        loginItemMenuItem.target = self
        menu.addItem(loginItemMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit shima", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let status = LoginItem.status
        Log.menu.info("menu launchAtLogin status=\(String(describing: status), privacy: .public)")
        let state = LoginItemMenu.state(for: status, registrationFailed: loginRegistrationFailed)
        loginItemMenuItem.title = state.title
        loginItemMenuItem.state = state.isOn ? .on : .off
        loginItemMenuItem.isEnabled = state.isEnabled
    }

    @objc private func toggleLoginItem() {
        let status = LoginItem.status
        let action = LoginItemMenu.action(for: status, registrationFailed: loginRegistrationFailed)
        Log.menu.info("menu launchAtLogin toggle from=\(String(describing: status), privacy: .public) action=\(String(describing: action), privacy: .public)")
        if !LoginItem.perform(action) { loginRegistrationFailed = true }
        Log.menu.info("menu launchAtLogin status after=\(String(describing: LoginItem.status), privacy: .public)")
    }
}
