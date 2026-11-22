import AppKit
import ShimaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let islandController = IslandPanelController()
    private lazy var spotify = SpotifyService(state: islandController.state, media: islandController.media)
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        showPanel()
        spotify.onLiveChange = { [weak self] in self?.islandController.setLive($0) }
        islandController.onIslandOpened = { [weak self] in self?.spotify.islandOpened() }
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
        menu.addItem(NSMenuItem(title: "Quit shima", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}
