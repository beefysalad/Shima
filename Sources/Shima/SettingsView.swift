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

    @Environment(\.colorScheme) private var colorScheme
    private var groupFill: Color { colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.035) }

    private let accent = Color(red: 0.76, green: 0.28, blue: 0.12)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(page.rawValue).font(.system(size: 24, weight: .bold))
                    Text(page.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.bottom, 24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
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
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: SettingsLayout.size.width, height: SettingsLayout.size.height)
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
            HStack(spacing: 9) {
                Image(systemName: "capsule.bottomhalf.filled")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("shima").font(.system(size: 18, weight: .bold))
                    Text("Settings").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(height: 40)
            .padding(.horizontal, 10)
            .padding(.top, 24)
            .padding(.bottom, 28)

            ForEach(SettingsPage.allCases, id: \.self) { item in
                Button { page = item } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.system(size: 13, weight: page == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(page == item ? accent : Color.clear, in: RoundedRectangle(cornerRadius: 7))
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
        .background(colorScheme == .dark ? Color.white.opacity(0.025) : Color.black.opacity(0.025))
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("STARTUP") {
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
            section("ISLAND") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Equalizer").font(.system(size: 13, weight: .medium))
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

    private var music: some View {
        section("SPOTIFY CONNECTION") {
            VStack(alignment: .leading, spacing: 16) {
                Label(model.spotifyRow.title, systemImage: model.spotifyRow.kind == .permissionDenied ? "exclamationmark.circle.fill" : "music.note")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.spotifyRow.kind == .permissionDenied ? Color.orange : Color.primary)
                Text(model.spotifyRow.detail)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(model.spotifyRow.buttonTitle) { model.openAutomationSettings() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var updates: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("SOFTWARE UPDATE") {
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
        VStack(alignment: .leading, spacing: 20) {
            section("SHIMA") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("A little more from your notch.").font(.system(size: 16, weight: .semibold))
                    Text(model.versionText).font(.system(size: 12)).foregroundStyle(.secondary)
                    Link("View on GitHub ↗", destination: URL(string: "https://github.com/beefysalad/Shima")!)
                        .font(.system(size: 12))
                }
            }
            section("SIGNING") {
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
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(.secondary)
                .padding(.leading, 2)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(groupFill, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
