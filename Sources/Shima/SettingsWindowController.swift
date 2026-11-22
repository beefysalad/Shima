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
    private let model: SettingsModel
    private let onToggleLogin: @MainActor () -> Void
    private var window: SettingsWindow?
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
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak window] in
            Log.settings.info("settings opened via \(entry.rawValue, privacy: .public) created=\(created, privacy: .public) active=\(NSApp.isActive, privacy: .public) key=\(window?.isKeyWindow ?? false, privacy: .public)")
        }
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
            model: model, onToggleLogin: onToggleLogin,
            onEqualizerMode: { [weak model] in model?.setEqualizerMode($0) },
            onSpotifyRow: { kind in Log.settings.info("settings spotify row=\(kind.rawValue, privacy: .public)") }))
        host.sizingOptions = []
        w.contentView = host
        w.setContentSize(SettingsLayout.size)
        Log.settings.info("settings window created")
        return w
    }
}
