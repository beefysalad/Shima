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
    var calendar: CalendarCoordinator? = nil

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
                CameraContent(service: camera, state: state)
            }
        }
        .overlay(alignment: .top) {
            if state.mode == .expanded && state.selectedTab == .calendar, let calendar {
                CalendarContent(coordinator: calendar)
            }
        }
        .overlay(alignment: .top) {
            HeaderTabIcon(state: state, onSettings: onSettings)
                .opacity(state.mode == .expanded ? 1 : 0)
                .allowsHitTesting(state.mode == .expanded)
        }
    }
}

/// Outlined 24-unit glyphs copied from mockup/index.html (stroke 1.7, round caps and joins).
enum HeaderGlyph { case home, music, camera, calendar }

struct HeaderGlyphShape: Shape {
    let glyph: HeaderGlyph

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGRect { CGRect(x: rect.minX + (x - r) * k, y: rect.minY + (y - r) * k, width: 2 * r * k, height: 2 * r * k) }
        var path = Path()
        switch glyph {
        case .home:
            path.move(to: p(4, 11)); path.addLine(to: p(12, 4)); path.addLine(to: p(20, 11)); path.addLine(to: p(20, 20))
            path.addLine(to: p(15, 20)); path.addLine(to: p(15, 14)); path.addLine(to: p(9, 14)); path.addLine(to: p(9, 20))
            path.addLine(to: p(4, 20)); path.closeSubpath()
        case .music:
            path.move(to: p(9, 18)); path.addLine(to: p(9, 6)); path.addLine(to: p(19, 4)); path.addLine(to: p(19, 16))
            path.addEllipse(in: circle(6.5, 18, 2.5)); path.addEllipse(in: circle(16.5, 16, 2.5))
        case .camera:
            path.move(to: p(4, 8)); path.addLine(to: p(7, 8)); path.addLine(to: p(8.5, 6)); path.addLine(to: p(15.5, 6))
            path.addLine(to: p(17, 8)); path.addLine(to: p(20, 8)); path.addLine(to: p(20, 19)); path.addLine(to: p(4, 19)); path.closeSubpath()
            path.addEllipse(in: circle(12, 13, 3.5))
        case .calendar:
            path.addRoundedRect(in: CGRect(x: rect.minX + 4 * k, y: rect.minY + 5 * k, width: 16 * k, height: 15 * k),
                                cornerSize: CGSize(width: 2.5 * k, height: 2.5 * k))
            path.move(to: p(4, 10)); path.addLine(to: p(20, 10))
            path.move(to: p(9, 3)); path.addLine(to: p(9, 7))
            path.move(to: p(15, 3)); path.addLine(to: p(15, 7))
        }
        return path
    }
}

/// The header strip left of the notch, as in the mockup: Home (opens Settings), Music, Camera.
/// Island-sized overlay, so it never changes the layout.
struct HeaderTabIcon: View {
    let state: AppState
    let onSettings: @MainActor () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            headerButton(.home, rect: NowPlayingLayout.settingsButton, selected: false, label: SettingsText.windowTitle) { onSettings() }
            ForEach(IslandTab.allCases, id: \.self) { tab in
                headerButton(Self.glyph(for: tab), rect: NowPlayingLayout.tabRect(tab),
                             selected: state.selectedTab == tab, label: Self.label(for: tab)) {
                    state.selectedTab = tab
                    Log.camera.info("camera tab clicked tab=\(tab.rawValue, privacy: .public) active=\(NSApp.isActive, privacy: .public)")
                }
            }
        }
        .frame(width: IslandLayout.expanded.width, height: IslandLayout.expanded.height, alignment: .topLeading)
    }

    private static func glyph(for tab: IslandTab) -> HeaderGlyph {
        switch tab {
        case .music: .music
        case .camera: .camera
        case .calendar: .calendar
        }
    }

    private static func label(for tab: IslandTab) -> String {
        switch tab {
        case .music: "Music"
        case .camera: "Camera"
        case .calendar: "Calendar"
        }
    }

    private func headerButton(_ glyph: HeaderGlyph, rect r: CGRect, selected: Bool, label: String, action: @escaping @MainActor () -> Void) -> some View {
        Button { action() } label: {
            HeaderGlyphShape(glyph: glyph)
                .stroke(Color.white.opacity(selected ? 1 : 0.52), style: StrokeStyle(lineWidth: 1.05, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 14)
                .frame(width: r.width, height: r.height)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(selected ? 0.13 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .position(x: r.midX, y: r.midY)
    }
}
