import SwiftUI
import ShimaCore

/// Kept in the hierarchy even while hidden so the equalizer retains its layer identity.
/// The equalizer stays at the same spot right of the notch while the island opens (Settings: equalizer mode).
struct WingsView: View {
    let state: AppState
    let media: IslandMedia
    let notchWidth: CGFloat

    private var equalizerVisible: Bool {
        EqualizerPolicy.isVisible(island: state.mode, live: state.live, content: state.content)
    }

    private var animating: Bool {
        EqualizerPolicy.isAnimating(state.equalizerMode, island: state.mode, live: state.live, content: state.content,
                                    playing: state.nowPlaying?.state == .playing, frozen: media.equalizerFrozen)
    }

    var body: some View {
        HStack(spacing: 0) {
            miniArtwork
                .frame(width: IslandLayout.liveWingWidth, height: 32)
                .opacity(state.live && state.mode == .collapsed ? 1 : 0)
            Color.clear
                .frame(width: notchWidth, height: 32)
            EqualizerView(animating: animating)
                .frame(width: NowPlayingLayout.equalizer.width, height: NowPlayingLayout.equalizer.height)
                .frame(width: IslandLayout.liveWingWidth, height: 32)
                .opacity(equalizerVisible ? 1 : 0)
        }
        .frame(width: notchWidth + 2 * IslandLayout.liveWingWidth, height: 32)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var miniArtwork: some View {
        Group {
            if let artwork = media.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: NowPlayingLayout.miniArtworkRadius)
                    .fill(Color.white.opacity(0.18))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
            }
        }
        .frame(width: NowPlayingLayout.miniArtwork.width, height: NowPlayingLayout.miniArtwork.height)
        .clipShape(RoundedRectangle(cornerRadius: NowPlayingLayout.miniArtworkRadius))
    }
}
