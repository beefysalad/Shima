import SwiftUI
import ShimaCore

/// Display content stays mounted for the island cross-fade; the timeline does not.
struct NowPlayingView: View {
    let state: AppState
    let media: IslandMedia
    let onCommand: @MainActor (SpotifyCommand) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch state.content {
            case .track:
                if let nowPlaying = state.nowPlaying {
                    track(nowPlaying)
                }
            case .notRunning:
                status("Spotify is not running")
            case .nothingPlaying:
                status("Nothing playing")
            case .permissionDenied:
                VStack(spacing: 6) {
                    Text("shima can't control Spotify")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.85))
                    Text("Allow it in System Settings › Privacy & Security › Automation")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(width: IslandLayout.expanded.width - 28, height: IslandLayout.expanded.height - 32)
                .position(x: IslandLayout.expanded.width / 2, y: 32 + (IslandLayout.expanded.height - 32) / 2)
            }
        }
        .frame(width: IslandLayout.expanded.width, height: IslandLayout.expanded.height)
    }

    private func track(_ nowPlaying: NowPlaying) -> some View {
        ZStack(alignment: .topLeading) {
            artwork
                .frame(width: NowPlayingLayout.artwork.width, height: NowPlayingLayout.artwork.height)
                .clipShape(RoundedRectangle(cornerRadius: NowPlayingLayout.artworkRadius))
                .position(x: NowPlayingLayout.artwork.midX, y: NowPlayingLayout.artwork.midY)

            HStack(spacing: 5) {
                BrandLogo(name: "SpotifyGreen")
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Text(nowPlaying.state == .playing ? "Playing on Spotify" : "Paused on Spotify")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .frame(width: NowPlayingLayout.column.width - 30, height: 14, alignment: .leading)
            .position(x: NowPlayingLayout.column.minX + (NowPlayingLayout.column.width - 30) / 2,
                      y: NowPlayingLayout.sourceTop + 7)

            Text(nowPlaying.title)
                .font(.system(size: NowPlayingLayout.titleSize, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: NowPlayingLayout.titleRect.width, height: 20, alignment: .leading)
                .position(x: NowPlayingLayout.titleRect.midX, y: NowPlayingLayout.titleRect.midY)

            Text(nowPlaying.album.isEmpty ? nowPlaying.artist : "\(nowPlaying.artist) · \(nowPlaying.album)")
                .font(.system(size: NowPlayingLayout.artistSize))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: NowPlayingLayout.column.width, height: 16, alignment: .leading)
                .position(x: NowPlayingLayout.column.midX, y: NowPlayingLayout.artistTop + 8)

            if state.mode == .expanded && nowPlaying.state == .playing {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let _ = Log.spotify.debug("progress tick")
                    progressRow(nowPlaying, at: context.date)
                }
            } else {
                progressRow(nowPlaying, at: Date())
            }
        }
        .overlay(alignment: .topLeading) { controls(nowPlaying) }
        .frame(width: IslandLayout.expanded.width, height: IslandLayout.expanded.height)
    }

    private func controls(_ nowPlaying: NowPlaying) -> some View {
        ZStack(alignment: .topLeading) {
            controlButton(.previous, symbol: "backward.fill", size: 13)
            controlButton(.playPause, symbol: nowPlaying.state == .playing ? "pause.fill" : "play.fill", size: 14)
                .background {
                    let r = NowPlayingLayout.controlRect(.playPause)
                    Circle().fill(Color.white.opacity(0.12))
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                }
            controlButton(.next, symbol: "forward.fill", size: 13)
        }
        .frame(width: IslandLayout.expanded.width, height: IslandLayout.expanded.height, alignment: .topLeading)
        .allowsHitTesting(state.mode == .expanded && state.content == .track)
    }

    private func controlButton(_ command: SpotifyCommand, symbol: String, size: CGFloat) -> some View {
        let r = NowPlayingLayout.controlRect(command)
        return Button { onCommand(command) } label: {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(.white)
                .frame(width: r.width, height: r.height)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(command == .previous ? "Previous track" : command == .next ? "Next track" : nowPlayingControlLabel)
        .frame(width: r.width, height: r.height)
        .position(x: r.midX, y: r.midY)
    }

    private var nowPlayingControlLabel: String {
        state.nowPlaying?.state == .playing ? "Pause" : "Play"
    }

    private var artwork: some View {
        Group {
            if let image = media.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: NowPlayingLayout.artworkRadius)
                    .fill(Color.white.opacity(0.18))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
            }
        }
        .accessibilityHidden(true)
    }

    private func progressRow(_ nowPlaying: NowPlaying, at date: Date) -> some View {
        let position = nowPlaying.position(at: date)
        let fraction = PlaybackTime.fraction(position: position, duration: nowPlaying.duration)
        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white)
                        .frame(width: NowPlayingLayout.column.width * fraction)
                }
                .frame(width: NowPlayingLayout.column.width, height: NowPlayingLayout.progressHeight)
                .position(x: NowPlayingLayout.column.midX,
                          y: NowPlayingLayout.progressTop + NowPlayingLayout.progressHeight / 2)
                .accessibilityHidden(true)

            HStack {
                Text(PlaybackTime.elapsed(position))
                Spacer(minLength: 0)
                Text(PlaybackTime.remaining(position: position, duration: nowPlaying.duration))
            }
            .font(.system(size: NowPlayingLayout.timesSize))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.45))
            .frame(width: NowPlayingLayout.column.width, height: 14)
            .position(x: NowPlayingLayout.column.midX, y: NowPlayingLayout.timesTop + 7)
        }
        .frame(width: IslandLayout.expanded.width, height: IslandLayout.expanded.height)
    }

    private func status(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundStyle(Color.white.opacity(0.6))
            .frame(width: IslandLayout.expanded.width - 28, height: IslandLayout.expanded.height - 32)
            .position(x: IslandLayout.expanded.width / 2, y: 32 + (IslandLayout.expanded.height - 32) / 2)
    }
}
