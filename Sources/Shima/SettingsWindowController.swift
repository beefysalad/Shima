import AppKit
import SwiftUI
import ShimaCore

/// Cmd-W closes the window (an accessory app has no main menu to provide it).
final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// The one Settings window (design 2026-11-22). Created on first show, then only ordered out and in.
/// Showing it is the only place shima activates itself; closing it hands activation back.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let updater = AppUpdater()
    private let model: SettingsModel
    private let onToggleLogin: @MainActor () -> Void
    private var window: SettingsWindow?
    private var pendingOpen: (entry: SettingsEntry, created: Bool)?
    /// The last other app that lost activation: the one to hand focus back to on close.
    private var lastOtherApp: NSRunningApplication?

    init(model: SettingsModel, onToggleLogin: @escaping @MainActor () -> Void) {
        self.model = model
        self.onToggleLogin = onToggleLogin
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appDeactivated(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
    }

    func show(via entry: SettingsEntry) {
        let created = window == nil
        let window = self.window ?? makeWindow()
        self.window = window
        model.refresh()
        Log.settings.info("settings refresh loginItem=\(String(describing: self.model.loginItemStatus), privacy: .public) spotify=\(self.model.spotifyRow.kind.rawValue, privacy: .public) eq=\(self.model.equalizerMode.rawValue, privacy: .public) loginControl=\(self.model.loginItem.isEnabled ? "enabled" : "disabled", privacy: .public) version=\"\(self.model.versionText, privacy: .public)\" signing=\"\(self.model.signingText, privacy: .public)\"")
        if !window.isVisible { placeOnPointerScreen(window) }
        pendingOpen = (entry, created)
        if NSApp.isActive, window.isKeyWindow {
            logOpened(window)      // already frontmost: no key change will follow
        } else {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)   // windowDidBecomeKey logs once activation has completed
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        logOpened(window)
    }

    private func logOpened(_ window: NSWindow) {
        guard let (entry, created) = pendingOpen else { return }
        pendingOpen = nil
        Log.settings.info("settings opened via \(entry.rawValue, privacy: .public) created=\(created, privacy: .public) active=\(NSApp.isActive, privacy: .public) key=\(window.isKeyWindow, privacy: .public)")
    }

    /// `center()` uses the window's current screen, so first move it to the screen under the pointer
    /// (else the island's screen, else the main one).
    private func placeOnPointerScreen(_ window: NSWindow) {
        let screens = NSScreen.screens
        let islandFrame = ScreenLocator.target().flatMap { ScreenLocator.screen(id: $0.id) }?.frame
        let islandIndex = islandFrame.flatMap { f in screens.firstIndex { $0.frame == f } }
        let mainIndex = NSScreen.main.flatMap { m in screens.firstIndex { $0.frame == m.frame } }
        if let i = ScreenPick.choose(pointer: NSEvent.mouseLocation, frames: screens.map(\.frame), island: islandIndex, main: mainIndex) {
            let f = screens[i].visibleFrame
            window.setFrameOrigin(NSPoint(x: f.midX - window.frame.width / 2, y: f.midY - window.frame.height / 2))
        }
        window.center()
    }

    func windowWillClose(_ notification: Notification) {
        var restored = "none"
        if NSApp.isActive, let app = lastOtherApp, !app.isTerminated {
            NSApp.yieldActivation(to: app)
            if app.activate(from: .current, options: []) {
                restored = app.bundleIdentifier ?? "pid \(app.processIdentifier)"
            }
        }
        let restoredName = restored
        DispatchQueue.main.async {
            let policy: String = switch NSApp.activationPolicy() {
            case .accessory: "accessory"
            case .regular: "regular"
            case .prohibited: "prohibited"
            @unknown default: "unknown"
            }
            Log.settings.info("settings closed policy=\(policy, privacy: .public) restored=\(restoredName, privacy: .public) active=\(NSApp.isActive, privacy: .public)")
        }
    }

    @objc nonisolated private func appDeactivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        MainActor.assumeIsolated { lastOtherApp = app }
    }

    private func makeWindow() -> SettingsWindow {
        let w = SettingsWindow(contentRect: NSRect(origin: .zero, size: SettingsLayout.size),
                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = SettingsText.windowTitle
        w.isReleasedWhenClosed = false
        w.tabbingMode = .disallowed
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        w.delegate = self
        let host = NSHostingView(rootView: SettingsView(
            model: model, updater: updater, onToggleLogin: onToggleLogin,
            onEqualizerMode: { [weak model] in model?.setEqualizerMode($0) },
            onSpotifyRow: { kind in Log.settings.info("settings spotify row=\(kind.rawValue, privacy: .public)") }))
        host.sizingOptions = []
        w.contentView = host
        w.setContentSize(SettingsLayout.size)
        Log.settings.info("settings window created")
        return w
    }
}
