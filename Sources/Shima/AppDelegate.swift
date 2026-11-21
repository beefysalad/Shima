import AppKit
import ShimaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let islandController = IslandPanelController()
    private var statusItem: NSStatusItem?

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
        menu.addItem(NSMenuItem(title: "Quit shima", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}
