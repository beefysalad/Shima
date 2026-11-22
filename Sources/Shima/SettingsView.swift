import SwiftUI
import ShimaCore

/// Native settings shell. Only pages backed by working features appear in the sidebar.
struct SettingsView: View {
    let model: SettingsModel
    let updater: AppUpdater
    @State private var confirmUpdate = false
    @State private var page: SettingsPage
    let onToggleLogin: @MainActor () -> Void
    let onEqualizerMode: @MainActor (EqualizerMode) -> Void
    let onSpotifyRow: @MainActor (SpotifyStatusKind) -> Void

    init(model: SettingsModel, updater: AppUpdater, initialPage: SettingsPage = .general,
         onToggleLogin: @escaping @MainActor () -> Void,
         onEqualizerMode: @escaping @MainActor (EqualizerMode) -> Void,
         onSpotifyRow: @escaping @MainActor (SpotifyStatusKind) -> Void) {
        self.model = model
        self.updater = updater
        self._page = State(initialValue: initialPage)
        self.onToggleLogin = onToggleLogin
        self.onEqualizerMode = onEqualizerMode
        self.onSpotifyRow = onSpotifyRow
    }

    private let accent = Color(red: 224 / 255, green: 122 / 255, blue: 79 / 255)
    private let groupFill = Color(red: 50 / 255, green: 50 / 255, blue: 52 / 255)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch page {
                        case .general: general
                        case .music: music
                        case .updates: updates
                        case .about: about
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.init(top: 18, leading: 22, bottom: 26, trailing: 22))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 38 / 255, green: 38 / 255, blue: 40 / 255))
        }
        .frame(width: SettingsLayout.size.width, height: SettingsLayout.size.height)
        .environment(\.colorScheme, .dark)
        .tint(accent)
        .confirmationDialog("Install the update and restart Shima?", isPresented: $confirmUpdate) {
            Button("Update and restart") { updater.install() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shima will close briefly. Spotify keeps playing. Your previous app is kept for recovery. Ad-hoc releases may require Spotify permission again.")
        }
        .onChange(of: model.spotifyRow.kind, initial: true) { _, kind in onSpotifyRow(kind) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 8) {
                BrandLogo(name: "ShimaBrand")
                    .frame(width: 64, height: 64)
                Text("shima").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .padding(.bottom, 20)

            ForEach(SettingsPage.allCases, id: \.self) { item in
                Button { page = item } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.symbol).frame(width: 21, height: 21)
                        Text(item.rawValue)
                    }
                        .font(.system(size: 13, weight: page == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(page == item ? accent : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(page == item ? Color.white : Color.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(page == item ? .isSelected : [])
                .padding(.bottom, 4)
            }
            Spacer()
            Divider().padding(.horizontal, 8).padding(.bottom, 12)
            Button { model.quit() } label: {
                Label(SettingsText.quitButton, systemImage: "power")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(width: SettingsLayout.sidebarWidth)
        .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255))
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Launch") {
                Toggle(isOn: Binding(get: { model.loginItem.isOn }, set: { _ in onToggleLogin() })) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Launch at login").font(.system(size: 13, weight: .medium))
                        Text(model.loginItem.isEnabled ? "Keep shima ready when you sign in." : model.loginItem.title)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .disabled(!model.loginItem.isEnabled)
            }
            section("Show") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show on a display").font(.system(size: 13))
                        Text("External monitors are not supported yet.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Built-in display").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            section("Displays without a notch") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hover zone").font(.system(size: 13))
                    Text("An invisible 200 × 32 pt zone at the top centre.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var music: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Spotify") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        BrandLogo(name: "SpotifyWhite").frame(width: 28, height: 28)
                        Text(model.spotifyRow.title).font(.system(size: 13, weight: .medium))
                        Spacer()
                        if model.spotifyRow.kind == .permissionDenied {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        }
                    }
                    Text(model.spotifyRow.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(model.spotifyRow.buttonTitle) { model.openAutomationSettings() }.buttonStyle(.bordered)
                }
            }
            section("Equalizer") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Animation").font(.system(size: 13, weight: .medium))
                    Text("Choose when the music bars animate.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Picker("Equalizer", selection: Binding(get: { model.equalizerMode }, set: onEqualizerMode)) {
                        ForEach(EqualizerMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var updates: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Software update") {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: updater.canInstall ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 25, weight: .light))
                            .foregroundStyle(accent)
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(updater.canInstall ? "A new version is ready" : "Keep shima up to date")
                                .font(.system(size: 14, weight: .semibold))
                            Text(updater.message)
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    Divider()
                    HStack(spacing: 10) {
                        if updater.busy { ProgressView().controlSize(.small) }
                        Button(updater.busy ? "Working…" : "Check for updates") { updater.check() }
                            .disabled(updater.busy)
                        if updater.canInstall {
                            Button("Update and restart…") { confirmUpdate = true }
                                .buttonStyle(.borderedProminent)
                                .disabled(updater.busy)
                        }
                    }
                    if let release = updater.release {
                        Link(updater.canInstall ? "What’s new ↗" : "View release ↗", destination: release.page)
                            .font(.system(size: 12))
                    }
                }
            }
            Label("Updates are checked only when you ask.", systemImage: "hand.raised")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text(model.versionText).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("shima") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        BrandLogo(name: "ShimaBrand").frame(width: 44, height: 44)
                        Text("shima").font(.system(size: 16, weight: .semibold))
                    }
                    Text(model.versionText).font(.system(size: 12)).foregroundStyle(.secondary)
                    Link("View on GitHub ↗", destination: URL(string: "https://github.com/beefysalad/Shima")!)
                        .font(.system(size: 12))
                }
            }
            section("Signing") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.signingText).font(.system(size: 12, weight: .medium))
                    Text("A consistent signing identity helps preserve Spotify permissions across updates.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.leading, 2)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(groupFill, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
