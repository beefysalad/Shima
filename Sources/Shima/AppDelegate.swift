import AppKit
import ShimaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let islandController = IslandPanelController()
    private lazy var spotify = SpotifyService(state: islandController.state, media: islandController.media)
    private var statusItem: NSStatusItem?
    private let environment = ProcessInfo.processInfo.environment
    private lazy var settings = SettingsModel(
        state: islandController.state,
        store: SettingsStore(storage: UserDefaultsPreferenceStorage.forShima(bundleIdentifier: Bundle.main.bundleIdentifier)),
        loginItems: SystemLoginItemService(),
        versionText: SettingsText.version(
            short: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String),
        bundlePath: Bundle.main.bundlePath,
        readSigning: { SigningInfo.read() })
    private lazy var settingsWindow = SettingsWindowController(
        model: settings, onToggleLogin: { [weak self] in self?.toggleLoginFromWindow() })
    private let loginItemMenuItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLoginItem), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.settings.info("settings eq mode=\(self.settings.equalizerMode.rawValue, privacy: .public) loaded")
        settings.onEqualizerModeChange = { mode in
            Log.settings.info("settings eq mode=\(mode.rawValue, privacy: .public) saved")
        }
        let dryOpen = environment["SHIMA_SETTINGS_DRY_OPEN"] != nil
        settings.onOpenURL = { url in
            Log.settings.info("settings open url=\(url.absoluteString, privacy: .public) dryRun=\(dryOpen, privacy: .public)")
            if !dryOpen { NSWorkspace.shared.open(url) }
        }
        settings.onQuit = {
            Log.settings.info("settings quit")
            NSApp.terminate(nil)
        }
        _ = settingsWindow
        setUpStatusItem()
        showPanel()
        spotify.onLiveChange = { [weak self] in self?.islandController.setLive($0) }
        spotify.onFakeEqualizerMode = { [weak self] in self?.settings.setEqualizerMode($0) }
        islandController.onIslandOpened = { [weak self] in self?.spotify.islandOpened() }
        islandController.onSettings = { [weak self] in self?.settingsWindow.show(via: .gear) }
        islandController.onCommand = { [weak self] in self?.spotify.perform($0) }
        spotify.start()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show(via: .reopen)
        return false
    }

    private func toggleLoginFromWindow() {
        let r = settings.toggleLaunchAtLogin()
        Log.settings.info("settings loginItem toggle from=\(String(describing: r.from), privacy: .public) action=\(String(describing: r.action), privacy: .public) ok=\(r.succeeded, privacy: .public) after=\(String(describing: r.after), privacy: .public)")
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
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        loginItemMenuItem.target = self
        menu.addItem(loginItemMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit shima", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        DispatchQueue.main.async { [weak self] in self?.logStatusItemFrame() }
    }

    @objc private func openSettingsFromMenu() { settingsWindow.show(via: .menu) }

    private func logStatusItemFrame() {
        guard let f = statusItem?.button?.window?.frame else { Log.menu.info("menu status item none"); return }
        let top = NSScreen.screens.first?.frame.maxY ?? f.maxY
        Log.menu.info("menu status item x=\(f.minX, format: .fixed(precision: 1), privacy: .public) y=\(top - f.maxY, format: .fixed(precision: 1), privacy: .public) w=\(f.width, format: .fixed(precision: 1), privacy: .public) h=\(f.height, format: .fixed(precision: 1), privacy: .public)")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        settings.refresh()
        Log.menu.info("menu launchAtLogin status=\(String(describing: self.settings.loginItemStatus), privacy: .public)")
        let state = settings.loginItem
        loginItemMenuItem.title = state.title
        loginItemMenuItem.state = state.isOn ? .on : .off
        loginItemMenuItem.isEnabled = state.isEnabled
    }

    @objc private func toggleLoginItem() {
        let r = settings.toggleLaunchAtLogin()
        Log.menu.info("menu launchAtLogin toggle from=\(String(describing: r.from), privacy: .public) action=\(String(describing: r.action), privacy: .public)")
        Log.menu.info("menu launchAtLogin status after=\(String(describing: r.after), privacy: .public)")
    }
}
