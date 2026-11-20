import AppKit
import ShimaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let islandController = IslandPanelController()
    private var statusItem: NSStatusItem?
    private let loginItemMenuItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLoginItem), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        showPanel()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

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
        let state = LoginItemMenu.state(for: LoginItem.status)
        loginItemMenuItem.title = state.title
        loginItemMenuItem.state = state.isOn ? .on : .off
        loginItemMenuItem.isEnabled = state.isEnabled
    }

    @objc private func toggleLoginItem() {
        LoginItem.perform(LoginItemMenu.action(for: LoginItem.status))
    }
}
