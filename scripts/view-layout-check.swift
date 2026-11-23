import AppKit
import AVFoundation
import SwiftUI
import ShimaCore

/// Measures the actual SwiftUI/AppKit output without Screen Recording or an onscreen window.
@main struct ViewLayoutCheck {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        // Replacing a root view can mount a new host before dismantling the old
        // one. Use an unattached layer: this regression opens no capture device.
        let sharedPreview = AVCaptureVideoPreviewLayer()
        let oldPreviewHost = CameraPreviewNSView(preview: sharedPreview)
        oldPreviewHost.frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        oldPreviewHost.layout()
        let newPreviewHost = CameraPreviewNSView(preview: sharedPreview)
        newPreviewHost.frame = CGRect(x: 0, y: 0, width: 332, height: 118)
        newPreviewHost.layout()
        let mountedFrame = sharedPreview.frame
        oldPreviewHost.layout()
        oldPreviewHost.setMirrored(false)
        CameraPreview.dismantleNSView(oldPreviewHost, coordinator: ())
        check(sharedPreview.superlayer === newPreviewHost.layer,
              "old preview host must not detach a replacement host's layer")
        check(sharedPreview.frame == mountedFrame && mountedFrame.size == newPreviewHost.bounds.size,
              "old preview host must not resize a replacement host's layer")
        CameraPreview.dismantleNSView(newPreviewHost, coordinator: ())
        check(sharedPreview.superlayer == nil, "current preview host must detach its own layer")
        print("preview replacement host ownership PASS (no capture session)")
        let state = AppState()
        state.live = true
        state.spotifyAvailability = .running
        state.nowPlaying = NowPlaying(trackID: "layout-check", title: "Layout check", artist: "Fixture",
            album: "", artworkURL: nil, duration: 180, position: 30, positionDate: .now, state: .paused)
        let camera = CameraService(state: state, environment: ["SHIMA_FAKE_CAMERA": "1"])
        defer { camera.shutdown() }
        let media = IslandMedia()
        media.equalizerFrozen = true
        media.artwork = NSImage(size: NSSize(width: 176, height: 176), flipped: false) { rect in
            NSColor.magenta.setFill()
            rect.fill()
            return true
        }
        let notch = CGRect(x: 646, y: 924, width: 179, height: 32)
        // Calendar tab with a fake client: the check never touches EventKit or asks for permission.
        let calendarClient = FakeCalendarClient(eventsAccess: .authorized, remindersAccess: .authorized)
        let calendarCoordinator = CalendarCoordinator(client: calendarClient, calendar: .autoupdatingCurrent, now: { Date() })
        state.addTabContextObserver { mode, tab in calendarCoordinator.setContext(mode: mode, tab: tab, screenAvailable: true) }
        let startOfToday = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        calendarClient.events = (1...5).map {
            CalendarEvent(id: "e\($0)", title: "Event \($0)", start: startOfToday.addingTimeInterval(Double($0) * 3600),
                          end: startOfToday.addingTimeInterval(Double($0) * 3600 + 1800), isAllDay: false, colorRGB: [0.3, 0.6, 1])
        }
        calendarClient.reminders = [ReminderItem(id: "r1", title: "Reminder", due: startOfToday, isCompleted: false)]
        let shelf = ShelfStore()
        let host = NSHostingView(rootView: IslandView(state: state, media: media,
            notch: notch, hasNotch: true, debug: false, hitOpacity: 0, onCommand: { _ in }, onSettings: {}, camera: camera,
            calendar: calendarCoordinator, shelf: shelf))
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
        window.setContentSize(NSSize(width: 436, height: 208))
        host.layoutSubtreeIfNeeded()
        let expandedRect = equalizer.convert(equalizer.bounds, to: host)
        check(expandedRect == CGRect(x: 316, y: 9, width: 16, height: 14), "expanded equalizer bounds: \(expandedRect)")
        let expanded = render(host)
        if CommandLine.arguments.contains("--snapshot") {
            let url = URL(fileURLWithPath: ".build/view-layout-regression/player.png")
            try! expanded.bitmap.representation(using: .png, properties: [:])!.write(to: url)
            print("Player preview: \(url.path)")
        }
        // The centre can contain text; scan the black silhouette at a blank column instead.
        let silhouette = expanded.rows(at: 162.5) { $0.alphaComponent > 0.9 }
        check(silhouette == 0..<200, "expanded silhouette rows: \(silhouette)")
        check(expanded.rows(in: 310..<340, ys: 0..<32, matching: isGreen) == 9..<23,
              "expanded equalizer (track shown) must sit right of the notch, rows 9..<23")
        check(expanded.rows(in: 82..<102, ys: 0..<32, matching: isMagenta).isEmpty, "expanded mini artwork must be hidden")
        state.spotifyAvailability = .notRunning
        host.layoutSubtreeIfNeeded()
        let notRunning = render(host)
        check(notRunning.rows(in: 310..<340, ys: 0..<32, matching: isGreen).isEmpty, "expanded equalizer must be hidden without a track")
        state.spotifyAvailability = .running
        host.layoutSubtreeIfNeeded()
        check(expanded.rows(at: 88.5, matching: isMagenta) == 50..<154, "expanded artwork must occupy y50..<154")
        for command in SpotifyCommand.allCases {
            let r = NowPlayingLayout.controlRect(command)
            let glyph = expanded.rows(in: Int(r.minX)..<Int(r.maxX), ys: 150..<190) { $0.alphaComponent > 0.9 && $0.redComponent > 0.9 && $0.greenComponent > 0.9 && $0.blueComponent > 0.9 }
            check(!glyph.isEmpty && glyph.lowerBound >= Int(r.minY) && glyph.upperBound <= Int(r.maxY), "\(command) glyph rows \(glyph) outside \(r)")
        }
        let gearRect = NowPlayingLayout.settingsButton.offsetBy(dx: (436 - IslandLayout.expanded.width) / 2, dy: 0)
        let gear = expanded.rows(in: Int(gearRect.minX)..<Int(gearRect.maxX), ys: 0..<32, matching: isGear)
        check(!gear.isEmpty && gear.lowerBound >= Int(gearRect.minY) && gear.upperBound <= Int(gearRect.maxY),
              "settings gear rows \(gear) outside \(gearRect)")
        print("settings gear at \(gearRect): glyph rows \(gear) PASS")
        let tabRect = NowPlayingLayout.tabIcon.offsetBy(dx: (436 - IslandLayout.expanded.width) / 2, dy: 0)
        let tabGlyph = expanded.rows(in: Int(tabRect.minX)..<Int(tabRect.maxX), ys: 0..<32, matching: isGear)
        check(!tabGlyph.isEmpty && tabGlyph.lowerBound >= Int(tabRect.minY) && tabGlyph.upperBound <= Int(tabRect.maxY),
              "home tab icon glyph rows \(tabGlyph) outside \(tabRect)")
        print("home tab icon at \(tabRect): glyph rows \(tabGlyph) PASS")
        // Camera stays inside the same root and leaves the existing gear untouched.
        state.selectedTab = .camera
        host.layoutSubtreeIfNeeded()
        let cameraPixels = render(host)
        let previewRect = NowPlayingLayout.cameraPreview.offsetBy(dx: 18, dy: 0)
        check(cameraPixels.rows(at: previewRect.midX, ys: 32..<200) { color in
            color.alphaComponent > 0.9 && color.blueComponent > 0.2 && color.greenComponent > 0.15
        } == Int(previewRect.minY)..<Int(previewRect.maxY), "camera gradient must fill preview height")
        check(cameraPixels.rows(at: 162.5) { $0.alphaComponent > 0.9 } == 0..<200,
              "camera must preserve expanded silhouette")
        check(cameraPixels.rows(in: Int(gearRect.minX)..<Int(gearRect.maxX), ys: 0..<32, matching: isGear) == gear,
              "camera must leave the settings gear unchanged")
        camera.fake?.permission = .denied
        camera.coordinator.refreshPermission()
        host.layoutSubtreeIfNeeded()
        let denied = render(host)
        check(!denied.rows(in: 50..<300, ys: 85..<110, matching: isGear).isEmpty,
              "denied camera must show inline recovery text")
        print("camera preview 258x146 + control column, unchanged silhouette/home button, denied text PASS")

        // Calendar tab: same root, header icon drawn, notch zone empty, grid inside the island even with six weeks.
        func notBlack(_ c: NSColor) -> Bool { c.alphaComponent > 0.9 && (c.redComponent > 0.12 || c.greenComponent > 0.12 || c.blueComponent > 0.12) }
        func isAccent(_ c: NSColor) -> Bool { c.alphaComponent > 0.9 && c.redComponent > 0.7 && c.redComponent - c.blueComponent > 0.35 && c.greenComponent > 0.2 && c.greenComponent < 0.65 }
        let shiftX = (436 - IslandLayout.expanded.width) / 2
        state.selectedTab = .calendar
        host.layoutSubtreeIfNeeded()
        let calendarPixels = render(host)
        check(calendarPixels.rows(at: 162.5) { $0.alphaComponent > 0.9 } == 0..<200, "calendar must preserve expanded silhouette")
        let calendarIcon = NowPlayingLayout.tabRect(.calendar).offsetBy(dx: shiftX, dy: 0)
        let calendarGlyph = calendarPixels.rows(in: Int(calendarIcon.minX)..<Int(calendarIcon.maxX), ys: 0..<32, matching: isGear)
        check(!calendarGlyph.isEmpty && calendarGlyph.lowerBound >= Int(calendarIcon.minY) && calendarGlyph.upperBound <= Int(calendarIcon.maxY),
              "calendar icon glyph rows \(calendarGlyph) outside \(calendarIcon)")
        check(calendarPixels.span(in: Int(110.5 + shiftX)..<Int(289.5 + shiftX), ys: 0..<32, matching: notBlack).isEmpty,
              "calendar tab must leave the notch zone empty")
        check(calendarPixels.span(in: Int(CalendarLayout.gridOrigin.x + shiftX)..<Int(386 + shiftX), ys: 72..<190, matching: isAccent).count >= 5,
              "calendar must draw today's number in the accent colour in the grid")
        let leftRows = calendarPixels.span(in: Int(18 + shiftX)..<Int(176 + shiftX), ys: 90..<190, matching: notBlack)
        check(!leftRows.isEmpty && leftRows.first! >= 90 && leftRows.last! < 186, "calendar rows must sit in y 90..186, got \(leftRows)")
        let grid = calendarPixels.span(in: Int(196 + shiftX)..<Int(386 + shiftX), ys: 60..<200, matching: notBlack)
        check(grid.last! < 187, "calendar grid must end by y 186, got \(grid)")
        // Six-week month (May 2026 needs 6 rows) and the denied state.
        for _ in 0..<12 { calendarCoordinator.showMonth(offset: -1) }
        host.layoutSubtreeIfNeeded()
        let browsed = render(host)
        let browsedGrid = browsed.span(in: Int(196 + shiftX)..<Int(386 + shiftX), ys: 60..<200, matching: notBlack)
        check(browsedGrid.last! < 187, "browsed months must keep the grid by y 186, got \(browsedGrid)")
        calendarCoordinator.goToToday()
        calendarClient.eventsAccess = .denied
        calendarClient.remindersAccess = .denied
        calendarCoordinator.refreshAccess()
        host.layoutSubtreeIfNeeded()
        let deniedCalendar = render(host)
        let notice = deniedCalendar.span(in: Int(18 + shiftX)..<Int(176 + shiftX), ys: 92..<180, matching: notBlack)
        check(!notice.isEmpty && notice.last! < 180, "denied calendar must show the two notices in y 92..180, got \(notice)")
        print("calendar tab: silhouette, header icon \(calendarIcon), empty notch zone, accent today number, rows y90..186, six-week grid by y186, denied notices PASS")
        calendarClient.eventsAccess = .authorized
        calendarClient.remindersAccess = .authorized
        calendarCoordinator.refreshAccess()
        // Home tab: same root, empty state then chips. Header strip and notch zone stay empty of content, the dot shows with items.
        let blueDot: (NSColor) -> Bool = { $0.alphaComponent > 0.9 && $0.blueComponent > 0.85 && $0.redComponent > 0.45 && $0.redComponent < 0.75 && $0.greenComponent > 0.6 && $0.greenComponent < 0.85 }
        let dotRect = ShelfLayout.homeDot.offsetBy(dx: shiftX, dy: 0)
        let dotXs = Int(dotRect.minX + 1)..<Int(dotRect.maxX - 1)
        let dotYs = Int(dotRect.minY + 1)..<Int(dotRect.maxY - 1)
        state.selectedTab = .home
        host.layoutSubtreeIfNeeded()
        let homeEmpty = render(host)
        check(homeEmpty.rows(at: 162.5) { $0.alphaComponent > 0.9 } == 0..<200, "home (empty) must preserve expanded silhouette")
        check(homeEmpty.rows(at: 88.5, matching: isMagenta).isEmpty, "home must hide the music artwork")
        let emptyRect = ShelfLayout.emptyState.offsetBy(dx: shiftX, dy: 0)
        let emptyInk = homeEmpty.span(in: Int(emptyRect.minX)..<Int(emptyRect.maxX), ys: 33..<200, matching: notBlack)
        check(!emptyInk.isEmpty && emptyInk.first! >= Int(emptyRect.minY) && emptyInk.last! < Int(ShelfLayout.countLabel.minY) + 20,
              "home empty state must draw inside y 44..186, got \(emptyInk.first ?? -1)...\(emptyInk.last ?? -1)")
        check(homeEmpty.span(in: Int(110.5 + shiftX)..<Int(289.5 + shiftX), ys: 0..<32, matching: notBlack).isEmpty, "home must leave the notch zone empty")
        check(homeEmpty.span(in: dotXs, ys: dotYs, matching: blueDot).isEmpty, "home dot must be hidden while the shelf is empty")
        let homeGlyph = homeEmpty.rows(in: Int(tabRect.minX)..<Int(tabRect.maxX), ys: 0..<32, matching: { $0.alphaComponent > 0.9 && $0.redComponent > 0.9 && $0.greenComponent > 0.9 && $0.blueComponent > 0.9 })
        check(!homeGlyph.isEmpty, "selected home icon must draw bright")
        let files = ["a.pdf", "b.png", "c.swift", "d.zip"].map { DroppedEntry(fileURL: URL(fileURLWithPath: "/nonexistent/\($0)")) }
        shelf.add(files + [DroppedEntry(string: "Some text"), DroppedEntry(url: URL(string: "https://example.com/x"))])
        host.layoutSubtreeIfNeeded()
        let homeChips = render(host)
        check(homeChips.rows(at: 162.5) { $0.alphaComponent > 0.9 } == 0..<200, "home (chips) must preserve expanded silhouette")
        if CommandLine.arguments.contains("--snapshot") {
            try! homeChips.bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/view-layout-regression/home.png"))
        }
        let chipRect = ShelfLayout.chipRow.offsetBy(dx: shiftX, dy: 0)
        let pdfBadge = homeChips.span(in: Int(chipRect.minX)..<Int(chipRect.minX) + 120, ys: 33..<200) { c in
            c.alphaComponent > 0.9 && c.redComponent > 0.85 && abs(c.greenComponent - 0.54) < 0.1 && abs(c.blueComponent - 0.5) < 0.1 }
        check(!pdfBadge.isEmpty && pdfBadge.first! >= Int(chipRect.minY) && pdfBadge.last! < Int(chipRect.maxY),
              "pdf badge must draw inside the chip row, got \(pdfBadge.first ?? -1)...\(pdfBadge.last ?? -1)")
        let chipInk = homeChips.span(in: Int(chipRect.minX)..<Int(chipRect.maxX), ys: 33..<200, matching: notBlack)
        check(chipInk.last! < Int(ShelfLayout.clearButton.maxY), "home content must end by y 188, got \(chipInk.last ?? -1)")
        check(!homeChips.span(in: Int(ShelfLayout.countLabel.minX + shiftX)..<Int(ShelfLayout.countLabel.maxX + shiftX), ys: Int(ShelfLayout.countLabel.minY)..<Int(ShelfLayout.countLabel.maxY), matching: notBlack).isEmpty,
              "home count label must draw")
        check(!homeChips.span(in: Int(ShelfLayout.clearButton.minX + shiftX)..<Int(ShelfLayout.clearButton.maxX + shiftX), ys: Int(ShelfLayout.clearButton.minY)..<Int(ShelfLayout.clearButton.maxY), matching: notBlack).isEmpty,
              "Clear button must draw")
        check(homeChips.span(in: Int(110.5 + shiftX)..<Int(289.5 + shiftX), ys: 0..<32, matching: notBlack).isEmpty, "home with chips must leave the notch zone empty")
        check(!homeChips.span(in: dotXs, ys: dotYs, matching: blueDot).isEmpty, "home dot must show while the shelf has items")
        check(homeChips.span(in: Int(gearRect.minX)..<Int(gearRect.maxX), ys: 0..<32, matching: isGear) == Array(gear.lowerBound..<gear.upperBound),
              "home must leave the settings gear unchanged")
        print("home tab: silhouette, empty state, chips with pdf badge, count, Clear, dot with items only, empty notch zone, content ends by y188 PASS")
        shelf.clear()
        // Drag veil: black below the header strip on any tab, Shelf tile grey / blue over / dimmed full; header strip untouched.
        state.selectedTab = .music
        let veilBlue: (NSColor) -> Bool = { $0.alphaComponent > 0.9 && $0.blueComponent > 0.55 && $0.blueComponent > $0.redComponent + 0.15 }
        let tileXs = Int(ShelfLayout.veilTile.minX + shiftX + 4)..<Int(ShelfLayout.veilTile.maxX + shiftX - 4)
        let tileYs = Int(ShelfLayout.veilTile.minY + 4)..<Int(ShelfLayout.veilTile.maxY - 4)
        let headerBefore = { (p: Pixels) in p.span(in: 0..<436, ys: 0..<32, matching: notBlack) }
        state.dragHovering = true
        state.veilOverTile = false
        host.layoutSubtreeIfNeeded()
        let veilNormal = render(host)
        check(veilNormal.rows(at: 162.5) { $0.alphaComponent > 0.9 } == 0..<200, "veil must preserve expanded silhouette")
        check(veilNormal.rows(at: 88.5, matching: isMagenta).isEmpty, "veil must cover the tab content (music artwork)")
        check(veilNormal.span(in: Int(4 + shiftX)..<Int(396 + shiftX), ys: 33..<200, matching: { $0.alphaComponent > 0.9 && $0.blueComponent > 0.6 && $0.redComponent < 0.2 }).isEmpty, "veil normal tile must not be blue")
        let tileInk = veilNormal.span(in: tileXs, ys: tileYs, matching: notBlack)
        check(!tileInk.isEmpty, "veil must draw the Shelf tile fill, icon and caption")
        check(!veilNormal.span(in: Int(ShelfLayout.veilCount.minX + shiftX)..<Int(ShelfLayout.veilCount.maxX + shiftX), ys: Int(ShelfLayout.veilCount.minY)..<Int(ShelfLayout.veilCount.maxY), matching: notBlack).isEmpty, "veil count line must draw")
        check(veilNormal.span(in: Int(110.5 + shiftX)..<Int(289.5 + shiftX), ys: 0..<32, matching: notBlack).isEmpty, "veil must leave the notch zone empty")
        check(veilNormal.span(in: Int(gearRect.minX)..<Int(gearRect.maxX), ys: 0..<32, matching: isGear) == Array(gear.lowerBound..<gear.upperBound), "veil must leave the header strip (gear) unchanged")
        check(veilNormal.span(in: Int(4 + shiftX)..<Int(396 + shiftX), ys: 33..<200, matching: notBlack).first.map { $0 >= Int(ShelfLayout.veilTile.minY) - 2 } ?? false,
              "veil content must start at the tile row (y>=50), none in 33..50")
        state.veilOverTile = true
        host.layoutSubtreeIfNeeded()
        let veilOver = render(host)
        check(!veilOver.span(in: tileXs, ys: tileYs, matching: veilBlue).isEmpty, "veil over tile must draw blue")
        check(headerBefore(veilOver) == headerBefore(veilNormal), "veil over tile must not touch the header strip")
        check(veilOver.rows(at: 162.5) { $0.alphaComponent > 0.9 } == 0..<200, "veil over tile must preserve expanded silhouette")
        shelf.add((0..<ShelfStore.cap).map { DroppedEntry(string: "t\($0)") })
        host.layoutSubtreeIfNeeded()
        let veilFull = render(host)
        check(shelf.isFull && veilFull.span(in: tileXs, ys: tileYs, matching: veilBlue).isEmpty, "full veil must not highlight the tile even when hovered")
        let fillXs = Int(ShelfLayout.veilTile.minX + shiftX + 6)..<Int(ShelfLayout.veilTile.minX + shiftX + 14)
        let fillYs = Int(ShelfLayout.veilTile.minY + 20)..<Int(ShelfLayout.veilTile.minY + 28)
        let tileFill: (NSColor) -> Bool = { $0.alphaComponent > 0.9 && $0.redComponent > 0.06 }
        check(!veilNormal.span(in: fillXs, ys: fillYs, matching: tileFill).isEmpty, "veil tile fill must be the grey fill")
        check(veilFull.span(in: fillXs, ys: fillYs, matching: tileFill).isEmpty, "full veil tile must be dimmed to half")
        shelf.clear()
        state.veilOverTile = false
        state.dragHovering = false
        host.layoutSubtreeIfNeeded()
        check(!render(host).rows(at: 88.5, matching: isMagenta).isEmpty, "veil must disappear when the drag ends")
        print("drag veil: covers content below y32, header strip and notch zone untouched, grey tile, blue over tile, dimmed and not blue when full, gone afterwards PASS")
        state.selectedTab = .music
        host.layoutSubtreeIfNeeded()

        state.selectedTab = .music
        state.mode = .collapsed
        host.layoutSubtreeIfNeeded()
        let hiddenCamera = render(host)
        check(hiddenCamera.rows(at: previewRect.midX, ys: 40..<186) { $0.greenComponent > 0.15 && $0.blueComponent > 0.2 }.isEmpty,
              "collapsed camera must be hidden")
        state.selectedTab = .music
        state.mode = .expanded
        host.layoutSubtreeIfNeeded()
        // The settings gear is an expanded-only control: the same frame rendered collapsed must show no glyph pixel.
        state.mode = .collapsed
        host.layoutSubtreeIfNeeded()
        let collapsedSameFrame = render(host)
        check(collapsedSameFrame.rows(in: Int(gearRect.minX)..<Int(gearRect.maxX), ys: 0..<32, matching: isGear).isEmpty,
              "collapsed island must not show the settings gear (436x208 frame)")
        state.mode = .expanded
        host.layoutSubtreeIfNeeded()
        print("expanded 436x208: silhouette 0..<200, equalizer 9..<23 with a track and hidden without, mini artwork hidden, artwork 50..<154 PASS")
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
        // Device banner (peek): the real island silhouette at 340 x 76 inside the 376 x 84 peek panel.
        let peekState = AppState()
        peekState.mode = .peek
        let peekHost = NSHostingView(rootView: IslandView(state: peekState, media: media,
            notch: notch, hasNotch: true, debug: false, hitOpacity: 0, onCommand: { _ in }, onSettings: {}))
        let peekWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 376, height: 84),
            styleMask: .borderless, backing: .buffered, defer: false)
        peekWindow.isOpaque = false
        peekWindow.backgroundColor = .clear
        peekWindow.contentView = peekHost
        let peekDX: CGFloat = (376 - IslandLayout.peek.width) / 2
        func peekPixels(_ kind: DeviceKind, _ name: String, _ battery: String?) -> Pixels {
            peekState.peek = .device(DevicePeek(title: "Connected", subtitle: name, batteryText: battery, kind: kind, duration: .seconds(3)))
            peekHost.layoutSubtreeIfNeeded()
            return render(peekHost)
        }
        func xs(_ r: CGRect) -> Range<Int> { Int(r.minX + peekDX)..<Int(r.maxX + peekDX) }
        func ys(_ r: CGRect) -> Range<Int> { Int(r.minY)..<Int(r.maxY) }
        func isWhite(_ c: NSColor) -> Bool { c.alphaComponent > 0.9 && c.redComponent > 0.85 && c.greenComponent > 0.85 && c.blueComponent > 0.85 }
        func isLight(_ c: NSColor) -> Bool { c.alphaComponent > 0.9 && c.redComponent > 0.4 && c.greenComponent > 0.4 && c.blueComponent > 0.4 }
        func isRed(_ c: NSColor) -> Bool { c.alphaComponent > 0.9 && c.redComponent > 0.8 && c.greenComponent < 0.55 && c.blueComponent < 0.5 }
        let blackCheck: (NSColor) -> Bool = { $0.alphaComponent > 0.9 }
        for kind in DeviceKind.allCases {
            let p = peekPixels(kind, "Test device", "82%")
            check(p.rows(at: 188, matching: blackCheck) == 0..<76, "\(kind) peek silhouette must be 76 rows high")
            check(!p.span(in: xs(PeekLayout.badge), ys: ys(PeekLayout.badge), matching: isWhite).isEmpty, "\(kind) badge glyph must be drawn")
            check(!p.span(in: xs(PeekLayout.title), ys: ys(PeekLayout.title), matching: isWhite).isEmpty, "\(kind) title must be drawn")
            check(!p.span(in: xs(PeekLayout.subtitle), ys: ys(PeekLayout.subtitle), matching: isLight).isEmpty, "\(kind) device name must be drawn")
            check(!p.span(in: xs(PeekLayout.batteryGroup), ys: ys(PeekLayout.batteryGroup), matching: isLight).isEmpty, "\(kind) battery must be drawn")
            check(p.span(in: Int(110.5 + peekDX)..<Int(289.5 + peekDX), ys: 0..<32, matching: { c in
                c.alphaComponent > 0.9 && (c.redComponent > 0.12 || c.greenComponent > 0.12 || c.blueComponent > 0.12) }).isEmpty,
                  "\(kind) peek must leave the notch strip empty")
            if CommandLine.arguments.contains("--snapshot") {
                try! p.bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/view-layout-regression/peek-\(kind.rawValue).png"))
            }
        }
        let noBattery = peekPixels(.keyboard, "Keychron K3", nil)
        check(noBattery.span(in: xs(PeekLayout.batteryGroup), ys: 40..<70, matching: { c in
            c.alphaComponent > 0.9 && (c.redComponent > 0.2 || c.greenComponent > 0.2 || c.blueComponent > 0.2) }).isEmpty,
              "no battery value must leave the battery area empty")
        if CommandLine.arguments.contains("--snapshot") {
            try! noBattery.bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/view-layout-regression/peek-nobattery.png"))
        }
        let inkCols = (0..<Int(IslandLayout.peek.width)).filter { x in
            !noBattery.span(in: (x + Int(peekDX))..<(x + Int(peekDX) + 1), ys: 38..<72, matching: { c in
                c.alphaComponent > 0.9 && (c.redComponent > 0.2 || c.greenComponent > 0.2 || c.blueComponent > 0.2) }).isEmpty }
        if let lo = inkCols.min(), let hi = inkCols.max() {
            let mid = Double(lo + hi + 1) / 2
            check(abs(mid - Double(IslandLayout.peek.width) / 2) <= 3, "no-battery banner must be centred (ink midpoint \(mid), island midpoint \(IslandLayout.peek.width / 2))")
        } else { check(false, "no-battery banner drew nothing") }
        let longName = peekPixels(.headphones, String(repeating: "Very Long Studio Headphones ", count: 3), "64%")
        check(longName.span(in: Int(252 + peekDX)..<Int(318 + peekDX), ys: 44..<64, matching: isLight).count >= 4,
              "battery text must stay readable beside a long name")
        check(longName.span(in: Int(318 + peekDX + 3)..<Int(IslandLayout.peek.width + peekDX), ys: 38..<72, matching: isLight).isEmpty,
              "a long name must not run past the battery group")
        let lowBattery = peekPixels(.earbuds, "AirPods", "5%")
        check(!lowBattery.span(in: xs(PeekLayout.batteryGroup), ys: ys(PeekLayout.batteryGroup), matching: isRed).isEmpty,
              "a battery at 15% or below must draw red")
        var noAnimation = Transaction()
        noAnimation.disablesAnimations = true // the real banner fades out; offscreen renders cannot advance an animation
        withTransaction(noAnimation) { peekState.mode = .collapsed }
        peekHost.layoutSubtreeIfNeeded()
        let peekGone = render(peekHost)
        check(peekGone.span(in: 0..<376, ys: 33..<84, matching: isLight).isEmpty, "the banner must be hidden outside a peek")
        print("peek banner 340x76 in 376x84: silhouette, SF Symbol badge for all \(DeviceKind.allCases.count) kinds, title, name, battery, empty notch strip, no-battery, long name, low battery red, hidden outside peek PASS")
        check(!window.isVisible && !peekWindow.isVisible, "diagnostic window must remain offscreen")
        print("cacheDisplay pixel checks PASS; no window shown")
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

    private static func isGear(_ color: NSColor) -> Bool {
        color.alphaComponent > 0.9 && color.redComponent > 0.45
            && abs(color.redComponent - color.greenComponent) < 0.05 && abs(color.greenComponent - color.blueComponent) < 0.05
    }

    private static func isGreen(_ color: NSColor) -> Bool {
        color.alphaComponent > 0.9 && color.greenComponent > 0.65 && color.redComponent < 0.6 && color.blueComponent < 0.65
    }

    private struct Pixels {
        let bitmap: NSBitmapImageRep
        let size: CGSize

        func rows(at x: CGFloat, ys: Range<Int>? = nil, matching predicate: (NSColor) -> Bool) -> Range<Int> {
            rows(in: Int(x)..<(Int(x) + 1), ys: ys, matching: predicate)
        }

        func rows(in xs: Range<Int>, ys: Range<Int>? = nil, matching predicate: (NSColor) -> Bool) -> Range<Int> {
            let r = span(in: xs, ys: ys, matching: predicate)
            if let first = r.first, let last = r.last {
                precondition(r.count == last - first + 1, "Pixel rows must be contiguous: \(r)")
                return first..<(last + 1)
            }
            return 0..<0
        }

        /// Every matching row, not necessarily contiguous (text with gaps between lines).
        func span(in xs: Range<Int>, ys: Range<Int>? = nil, matching predicate: (NSColor) -> Bool) -> [Int] {
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
            return matches
        }
    }
}
