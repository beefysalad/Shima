import SwiftUI
import ShimaCore

/// Fixed layout (SettingsLayout) so scripts can click by coordinates. No timers; the Spotify row
/// follows AppState through Observation.
struct SettingsView: View {
    let model: SettingsModel
    let onToggleLogin: @MainActor () -> Void
    let onEqualizerMode: @MainActor (EqualizerMode) -> Void
    let onSpotifyRow: @MainActor (SpotifyStatusKind) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            header("General", SettingsLayout.generalHeader)
            Toggle(model.loginItem.title, isOn: Binding(get: { model.loginItem.isOn }, set: { _ in onToggleLogin() }))
                .toggleStyle(.checkbox)
                .disabled(!model.loginItem.isEnabled)
                .place(SettingsLayout.launchAtLogin)
            Text("Equalizer").place(SettingsLayout.equalizerLabel)
            ForEach(EqualizerMode.allCases, id: \.self) { mode in
                segment(mode).place(SettingsLayout.equalizerSegment(mode))
            }

            header("Spotify", SettingsLayout.spotifyHeader)
            Text(model.spotifyRow.title).font(.system(size: 13, weight: .medium)).place(SettingsLayout.spotifyTitle)
            Text(model.spotifyRow.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                .lineLimit(2).place(SettingsLayout.spotifyDetail)
            automationButton.place(SettingsLayout.automationButton)

            header("About", SettingsLayout.aboutHeader)
            Text(model.versionText).font(.system(size: 12)).place(SettingsLayout.version)
            Text(model.signingText).font(.system(size: 12)).foregroundStyle(.secondary).place(SettingsLayout.signing)
            Button { model.quit() } label: {
                Text(SettingsText.quitButton).frame(width: SettingsLayout.quitButton.width - 16)
            }
            .place(SettingsLayout.quitButton)
        }
        .frame(width: SettingsLayout.size.width, height: SettingsLayout.size.height, alignment: .topLeading)
        .onChange(of: model.spotifyRow.kind, initial: true) { _, kind in onSpotifyRow(kind) }
    }

    private func header(_ title: String, _ rect: CGRect) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold)).place(rect)
    }

    private func segment(_ mode: EqualizerMode) -> some View {
        let selected = model.equalizerMode == mode
        return Button { onEqualizerMode(mode) } label: {
            Text(mode.title)
                .font(.system(size: 12))
                .frame(width: 86, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor : Color.secondary.opacity(0.15)))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var automationButton: some View {
        let label = Text(model.spotifyRow.buttonTitle).frame(width: SettingsLayout.automationButton.width - 16)
        if model.spotifyRow.buttonProminent {
            Button { model.openAutomationSettings() } label: { label }.buttonStyle(.borderedProminent)
        } else {
            Button { model.openAutomationSettings() } label: { label }.buttonStyle(.bordered)
        }
    }
}

private extension View {
    func place(_ r: CGRect) -> some View {
        frame(width: r.width, height: r.height, alignment: .leading).position(x: r.midX, y: r.midY)
    }
}
