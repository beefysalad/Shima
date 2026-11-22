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
            Text("shima")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, notch.height + 12)
                .opacity(state.mode == .expanded ? 1 : 0)
            if debug {
                Rectangle().strokeBorder(Color.red.opacity(0.6), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
