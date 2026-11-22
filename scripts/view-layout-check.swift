import AppKit
import SwiftUI
import ShimaCore

/// Measures the actual SwiftUI/AppKit output without Screen Recording or an onscreen window.
@main struct ViewLayoutCheck {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let expectsNowPlaying = true // --now-playing is the default since the Settings milestone; the flag is still accepted
        let state = AppState()
        state.live = true
        state.spotifyAvailability = .running
        state.nowPlaying = NowPlaying(trackID: "layout-check", title: "Layout check", artist: "Fixture",
            album: "", artworkURL: nil, duration: 180, position: 30, positionDate: .now, state: .paused)
        let media = IslandMedia()
        media.equalizerFrozen = true
        media.artwork = NSImage(size: NSSize(width: 176, height: 176), flipped: false) { rect in
            NSColor.magenta.setFill()
            rect.fill()
            return true
        }
        let notch = CGRect(x: 646, y: 924, width: 179, height: 32)
        let host = NSHostingView(rootView: IslandView(state: state, media: media,
            notch: notch, hasNotch: true, debug: false, hitOpacity: 0, onCommand: { _ in }))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 245, height: 32),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let equalizer = findEqualizer(host) else { fatalError("Equalizer missing") }
        let rect = equalizer.convert(equalizer.bounds, to: host)
        print("live equalizer bounds: \(rect)")

        // Only this diagnostic instance: expose full bar bounds as static pixels.
        // Normal frozen bars have a quarter-height rest transform; production is untouched.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in equalizer.layer?.sublayers ?? [] { bar.transform = CATransform3DIdentity }
        CATransaction.commit()
        let live = render(host)
        let black = live.rows(at: 122.5) { $0.alphaComponent > 0.9 && $0.redComponent < 0.05 && $0.greenComponent < 0.05 && $0.blueComponent < 0.05 }
        let artwork = live.rows(at: 16.5, matching: isMagenta)
        let bars = live.rows(in: 220..<237, matching: isGreen)
        print("live pixel rows: black=\(black), artwork=\(artwork), equalizer=\(bars)")
        check(rect == CGRect(x: 220.5, y: 9, width: 16, height: 14), "live equalizer bounds: \(rect)")
        check(black == 0..<32, "live black rows: \(black)")
        check(artwork == 6..<26, "live artwork rows: \(artwork)")
        check(bars == 9..<23, "live equalizer pixel rows: \(bars)")
        print("live 245x32: black 0..<32, artwork 6..<26, equalizer 9..<23 PASS")

        state.mode = .expanded
        window.setContentSize(NSSize(width: 396, height: 173))
        host.layoutSubtreeIfNeeded()
        let expandedRect = equalizer.convert(equalizer.bounds, to: host)
        check(expandedRect == CGRect(x: 296, y: 9, width: 16, height: 14), "expanded equalizer bounds: \(expandedRect)")
        let expanded = render(host)
        // The centre can contain text; scan the black silhouette at a blank column instead.
        let silhouette = expanded.rows(at: 150.5) { $0.alphaComponent > 0.9 }
        check(silhouette == 0..<165, "expanded silhouette rows: \(silhouette)")
        check(expanded.rows(in: 290..<320, ys: 0..<32, matching: isGreen) == 9..<23,
              "expanded equalizer (track shown) must sit right of the notch, rows 9..<23")
        check(expanded.rows(in: 82..<102, ys: 0..<32, matching: isMagenta).isEmpty, "expanded mini artwork must be hidden")
        state.spotifyAvailability = .notRunning
        host.layoutSubtreeIfNeeded()
        let notRunning = render(host)
        check(notRunning.rows(in: 290..<320, ys: 0..<32, matching: isGreen).isEmpty, "expanded equalizer must be hidden without a track")
        state.spotifyAvailability = .running
        host.layoutSubtreeIfNeeded()
        if expectsNowPlaying {
            check(expanded.rows(at: 76.5, matching: isMagenta) == 44..<132, "expanded artwork must occupy y44..<132")
            for command in SpotifyCommand.allCases {
                let r = NowPlayingLayout.controlRect(command)
                let glyph = expanded.rows(in: Int(r.minX)..<Int(r.maxX), ys: 100..<160) { $0.alphaComponent > 0.9 && $0.redComponent > 0.9 && $0.greenComponent > 0.9 && $0.blueComponent > 0.9 }
                check(!glyph.isEmpty && glyph.lowerBound >= Int(r.minY) && glyph.upperBound <= Int(r.maxY), "\(command) glyph rows \(glyph) outside \(r)")
            }
        }
        print("expanded 396x173: silhouette 0..<165, equalizer 9..<23 with a track and hidden without, mini artwork hidden, artwork 44..<132 PASS")
        state.mode = .collapsed
        state.live = false
        window.setContentSize(NSSize(width: 179, height: 32))
        host.layoutSubtreeIfNeeded()
        let idle = render(host)
        let idleBlack = idle.rows(at: 89.5) { $0.alphaComponent > 0.9 && $0.redComponent < 0.05 && $0.greenComponent < 0.05 && $0.blueComponent < 0.05 }
        check(idleBlack == 0..<32, "not-live black rows: \(idleBlack)")
        check(idle.rows(in: 0..<179, matching: isMagenta).isEmpty, "not-live artwork must be hidden")
        check(idle.rows(in: 0..<179, matching: isGreen).isEmpty, "not-live equalizer must be hidden")
        print("not-live 179x32: black 0..<32, no wings content PASS")
        check(!window.isVisible, "diagnostic window must remain offscreen")
        print("cacheDisplay pixel checks PASS; no window shown, no image file written")
    }

    @MainActor private static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            print("FAIL: \(message)")
            fflush(nil)
            exit(1)
        }
    }

    @MainActor private static func findEqualizer(_ view: NSView) -> EqualizerNSView? {
        if let equalizer = view as? EqualizerNSView { return equalizer }
        return view.subviews.lazy.compactMap(findEqualizer).first
    }

    @MainActor private static func render(_ host: NSView) -> Pixels {
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No cacheDisplay bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return Pixels(bitmap: bitmap, size: host.bounds.size)
    }

    private static func isMagenta(_ color: NSColor) -> Bool {
        color.alphaComponent > 0.9 && color.redComponent > 0.7 && color.greenComponent < 0.5 && color.blueComponent > 0.7
    }

    private static func isGreen(_ color: NSColor) -> Bool {
        color.alphaComponent > 0.9 && color.greenComponent > 0.65 && color.redComponent < 0.6 && color.blueComponent < 0.65
    }

    private struct Pixels {
        let bitmap: NSBitmapImageRep
        let size: CGSize

        func rows(at x: CGFloat, matching predicate: (NSColor) -> Bool) -> Range<Int> {
            rows(in: Int(x)..<(Int(x) + 1), matching: predicate)
        }

        func rows(in xs: Range<Int>, ys: Range<Int>? = nil, matching predicate: (NSColor) -> Bool) -> Range<Int> {
            let scaleX = CGFloat(bitmap.pixelsWide) / size.width
            let scaleY = CGFloat(bitmap.pixelsHigh) / size.height
            var matches: [Int] = []
            for y in (ys ?? 0..<Int(size.height)) {
                for x in xs {
                    guard let color = bitmap.colorAt(x: Int((CGFloat(x) + 0.5) * scaleX),
                        y: Int((CGFloat(y) + 0.5) * scaleY))?.usingColorSpace(.sRGB) else { continue }
                    if predicate(color) { matches.append(y); break }
                }
            }
            guard let first = matches.first, let last = matches.last else { return 0..<0 }
            precondition(matches.count == last - first + 1, "Pixel rows must be contiguous: \(matches)")
            return first..<(last + 1)
        }
    }
}
