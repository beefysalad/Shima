import AppKit
import SwiftUI
import ShimaCore

/// Renders the Settings window's pages offscreen (no window, no Screen Recording) to PNG for comparison with mockup/index.html.
/// Usage: render-settings <output-dir>
@MainActor final class StubLogin: LoginItemService {
    var status: LoginItemStatus = .notRegistered
    func perform(_ action: LoginItemAction) -> Bool { true }
}

@main struct RenderSettings {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let out = CommandLine.arguments.dropFirst().first ?? "."
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let model = SettingsModel(state: AppState(), store: SettingsStore(storage: InMemoryPreferenceStorage()),
                                  loginItems: StubLogin(), versionText: "Version 0 (0)", readSigning: { .adHoc })
        model.refresh()
        for (name, enabled) in [("popups-on", true), ("popups-off", false)] {
            model.setDevicePopupsEnabled(enabled)
            let host = NSHostingView(rootView: SettingsView(model: model, updater: AppUpdater(), initialPage: .general,
                onToggleLogin: {}, onEqualizerMode: { _ in }, onSpotifyRow: { _ in })
                .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: SettingsLayout.size), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            host.displayIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/settings-general-\(name).png"))
            print("rendered \(name)")
            window.close()
        }
    }
}
