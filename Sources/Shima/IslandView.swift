import SwiftUI
import ShimaCore

struct IslandShape: Shape {
    var metrics: IslandShapeMetrics

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            .init(.init(metrics.width, metrics.height), .init(metrics.bottomRadius, metrics.earRadius))
        }
        set {
            metrics = IslandShapeMetrics(
                width: newValue.first.first, height: newValue.first.second,
                bottomRadius: newValue.second.first, earRadius: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        Path(IslandPath.make(in: rect, metrics: metrics))
    }
}

struct IslandView: View {
    let state: AppState
    let media: IslandMedia
    let notch: CGRect
    let hasNotch: Bool
    let debug: Bool
    let hitOpacity: Double
    let onCommand: @MainActor (SpotifyCommand) -> Void
    let onSettings: @MainActor () -> Void
    var camera: CameraService? = nil

    private var fill: Color {
        if debug { return Color.red.opacity(0.85) }
        if state.mode == .collapsed && !hasNotch && !state.live {
            return Color.black.opacity(hitOpacity == 0 ? 0.001 : hitOpacity)
        }
        return Color.black
    }

    var body: some View {
        ZStack(alignment: .top) {
            if state.mode == .expanded && hitOpacity > 0 {
                Rectangle().fill(Color.black.opacity(hitOpacity))
            }
            IslandShape(metrics: IslandLayout.metrics(for: state.mode, notch: notch, live: state.live))
                .fill(fill)
            WingsView(state: state, media: media, notchWidth: notch.width)
            if debug {
                Rectangle().strokeBorder(Color.red.opacity(0.6), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .top) {
            NowPlayingView(state: state, media: media, onCommand: onCommand)
                .opacity(state.mode == .expanded && state.selectedTab == .music ? 1 : 0)
                .allowsHitTesting(state.mode == .expanded && state.selectedTab == .music)
        }
        .overlay(alignment: .top) {
            if state.mode == .expanded && state.selectedTab == .camera, let camera {
                CameraContent(service: camera)
            }
        }
        .overlay(alignment: .top) {
            HeaderTabIcon(state: state)
                .opacity(state.mode == .expanded ? 1 : 0)
                .allowsHitTesting(state.mode == .expanded)
        }
        .overlay(alignment: .top) {
            SettingsGear(action: onSettings)
                .opacity(state.mode == .expanded ? 1 : 0)
                .allowsHitTesting(state.mode == .expanded)
        }
    }
}

/// The settings gear of the open island: island-sized so it never changes the layout, one button at `settingsButton`.
struct SettingsGear: View {
    let action: @MainActor () -> Void

    var body: some View {
        let r = NowPlayingLayout.settingsButton
        ZStack(alignment: .topLeading) {
            Button { action() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: r.width, height: r.height)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(SettingsText.windowTitle)
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
        }
        .frame(width: IslandLayout.expanded.width, height: IslandLayout.expanded.height, alignment: .topLeading)
    }
}

/// Island-sized overlay preserves the root layout and the original header position.
struct HeaderTabIcon: View {
    let state: AppState

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach([IslandTab.music, .camera], id: \.self) { tab in
                let r = NowPlayingLayout.tabRect(tab)
                Button {
                    state.selectedTab = tab
                    Log.camera.info("camera tab clicked tab=\(tab.rawValue, privacy: .public) active=\(NSApp.isActive, privacy: .public)")
                } label: {
                    Group {
                        if tab == .music {
                            BrandLogo(name: "SpotifyWhite").frame(width: 21, height: 21)
                        } else {
                            Image(systemName: "camera.fill").font(.system(size: 15))
                        }
                    }
                    .foregroundStyle(.white.opacity(state.selectedTab == tab ? 1 : 0.65))
                    .frame(width: r.width, height: r.height)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(state.selectedTab == tab ? 0.13 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab == .music ? "Music" : "Camera")
                .accessibilityAddTraits(state.selectedTab == tab ? .isSelected : [])
                .position(x: r.midX, y: r.midY)
            }
        }
        .frame(width: IslandLayout.expanded.width, height: IslandLayout.expanded.height, alignment: .topLeading)
    }
}
