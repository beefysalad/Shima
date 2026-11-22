import AppKit
import ShimaCore

/// Global top-left CGEvent points using the app's actual target and layout.
@main struct IslandInputGeometry {
    @MainActor static func main() {
        guard let display = ScreenLocator.target(), let primary = NSScreen.screens.first else {
            fputs("No built-in island target; refusing pointer checks.\n", stderr)
            exit(2)
        }
        let notch = display.notchRect
        let top = primary.frame.maxY - notch.maxY
        let mid = notch.midX
        let left = mid - IslandLayout.expanded.width / 2
        let music = NowPlayingLayout.tabRect(.music)
        let camera = NowPlayingLayout.tabRect(.camera)
        let mirror = NowPlayingLayout.cameraMirror
        let previous = NowPlayingLayout.controlRect(.previous)
        let play = NowPlayingLayout.controlRect(.playPause)
        let next = NowPlayingLayout.controlRect(.next)
        print(left + music.midX, left + camera.midX, top + music.midY,
              mid, top + notch.height / 2, top + IslandLayout.expanded.height + 200,
              left + mirror.midX, top + mirror.midY,
              left + previous.midX, top + previous.midY,
              left + play.midX, top + play.midY,
              left + next.midX, top + next.midY,
              left + NowPlayingLayout.artwork.midX, top + NowPlayingLayout.artwork.midY)
    }
}
