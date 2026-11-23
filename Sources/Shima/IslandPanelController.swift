import AppKit
import SwiftUI
import ShimaCore

@MainActor
final class IslandPanelController {
    private static let debug = ProcessInfo.processInfo.environment["SHIMA_DEBUG"] != nil
    /// Spike 1: a fully transparent hot zone still receives tracking events.
    private static let hitOpacity: Double = 0
    private static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)

    private enum FrameKind: String {
        case idle, peek, expanded
    }

    /// Created lazily on the first non-nil `place`, then kept (only ordered out/in).
    private var panel: NotchPanel?
    private let trackingView = HoverTrackingView()
    private let hostingView: ClickHostingView<IslandView>
    let state = AppState()
    let media = IslandMedia()
    var camera: CameraService?
    var calendar: CalendarService?
    var shelfService: ShelfService?
    var onCommand: (@MainActor (SpotifyCommand) -> Void)?
    var onSettings: (@MainActor () -> Void)?
    var onIslandOpened: (@MainActor () -> Void)?
    private var hover: HoverController!
    private var notch: CGRect = .zero
    private var hasNotch = false
    private var region: HotRegion = .idle
    /// Target live flag; `state.live` is the applied one and only changes while the panel is small.
    private var desiredLive = false


    init() {
        hostingView = ClickHostingView(rootView: IslandView(
            state: state, media: media, notch: .zero, hasNotch: false,
            debug: Self.debug, hitOpacity: Self.hitOpacity, onCommand: { _ in }, onSettings: {}))
        hostingView.frame = trackingView.bounds
        hostingView.autoresizingMask = [.width, .height]
        trackingView.addSubview(hostingView)

        state.onArtworkChange = { [weak media] trackID, url in
            media?.artworkCache.show(trackID: trackID, url: url)
        }

        hover = HoverController(scheduler: DispatchScheduler()) { [weak self] effect in
            self?.perform(effect)
        }
        hover.onPhaseChange = { [weak self] from, to in
            Log.hover.debug("hover \(String(describing: from), privacy: .public) -> \(String(describing: to), privacy: .public)")
            guard let self else { return }
            self.state.dragHovering = (to == .dragHovering)
            if to != .dragHovering { self.state.veilOverTile = false }
        }
        trackingView.onPointer = { [weak self] inside in
            self?.hover.pointer(inside: inside)
        }
        trackingView.onDragEvent = { [weak self] in self?.shelfDrag($0) }
        trackingView.onDrop = { [weak self] entries in
            self?.shelfService?.drop(entries) ?? ShelfAddResult(added: 0, refused: 0)
        }
        trackingView.onDragLocation = { [weak self] point in
            guard let self else { return }
            let over = point.map(ShelfLayout.isOverVeilTile) ?? false
            if self.state.veilOverTile != over { self.state.veilOverTile = over }
        }
    }

    /// Desired live flag from Spotify. Never changes the frame directly: the hover
    /// machine decides when the panel is small and answers with `.shrinkPanel`.
    func setLive(_ live: Bool) {
        guard live != desiredLive else { return }
        desiredLive = live
        Log.layout.info("live desired=\(live, privacy: .public)")
        hover.idleGeometryChanged()
    }

    func showPeek(_ item: PeekItem, duration: Duration) -> Bool {
        let previous = state.peek
        let replacesVisiblePeek = state.mode == .peek
        state.peek = item
        guard hover.peek(duration: duration) else {
            state.peek = previous
            Log.peek.info("peek dropped")
            return false
        }
        // Replacing visible content restarts the timer without another entrance animation.
        if replacesVisiblePeek { logPeekShown(item) }
        return true
    }

    func place(on display: DisplayDescriptor?) {
        guard let display else {
            hover.reset()
            panel?.orderOut(nil)
            Log.display.info("display none: panel hidden")
            return
        }
        let panel = ensurePanel()
        notch = display.notchRect
        hasNotch = display.hasNotch
        let r = notch
        Log.display.info("display built-in notch=\(display.hasNotch, privacy: .public) rect=\(r.minX, format: .fixed(precision: 1), privacy: .public),\(r.minY, format: .fixed(precision: 1), privacy: .public),\(r.width, format: .fixed(precision: 1), privacy: .public),\(r.height, format: .fixed(precision: 1), privacy: .public)")
        hostingView.rootView = IslandView(
            state: state, media: media, notch: notch, hasNotch: hasNotch,
            debug: Self.debug, hitOpacity: Self.hitOpacity,
            onCommand: { [weak self] in self?.handle($0) },
            onSettings: { [weak self] in self?.openSettings() }, camera: camera, calendar: calendar?.coordinator,
            shelf: shelfService?.store, shelfService: shelfService)
        hover.reset()
        applyIdleGeometry(animated: false) // always re-applied, even if unchanged
        panel.orderFrontRegardless()
    }

    private func handle(_ command: SpotifyCommand) {
        Log.spotify.info("spotify command \(command.rawValue, privacy: .public) active=\(NSApp.isActive, privacy: .public) key=\(self.panel?.isKeyWindow ?? false, privacy: .public)")
        onCommand?(command)
    }

    /// Drag events from the shelf service (fake driver now, the drop destination view in Task 8).
    func shelfDrag(_ event: ShelfDragEvent) {
        switch event {
        case .entered: hover.dragEntered()
        case .exited: hover.dragExited()
        case .ended(let dropped): hover.dragEnded(dropped: dropped)
        }
    }

    private func openSettings() {
        Log.settings.info("settings gear clicked active=\(NSApp.isActive, privacy: .public) key=\(self.panel?.isKeyWindow ?? false, privacy: .public)")
        onSettings?()
    }

    private func ensurePanel() -> NotchPanel {
        if let panel { return panel }
        let p = NotchPanel(contentRect: .zero)
        p.contentView = trackingView
        panel = p
        return p
    }

    private func perform(_ effect: HoverEffect) {
        switch effect {
        case .growPanel:
            setPanelFrame(.expanded, live: state.live)
        case .growPanelForPeek:
            setPanelFrame(.peek, live: state.live)
        case .shrinkPanel:
            applyIdleGeometry(animated: true)
        case .setHotRegion(let r):
            region = r
            refreshHotRect()
        case .animatePeekIn:
            withAnimation(Self.spring) { state.mode = .peek }
            if let item = state.peek { logPeekShown(item) }
        case .animateExpand:
            withAnimation(Self.spring) {
                dismissPeek()
                state.mode = .expanded
            }
            let content = String(describing: state.content)
            Log.layout.info("island content=\(content, privacy: .public)")
            onIslandOpened?()
        case .animateCollapse(let generation):
            withAnimation(Self.spring, completionCriteria: .removed) {
                dismissPeek()
                state.mode = .collapsed
            } completion: { [weak self] in
                self?.hover.collapseFinished(generation: generation)
            }
        case .snapCollapsed:
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                dismissPeek()
                state.mode = .collapsed
            }
        case .startTimer, .cancelTimer:
            break // consumed by HoverController
        }
    }

    private func logPeekShown(_ item: PeekItem) {
        switch item {
        case .device(let device):
            Log.peek.info("peek shown \(device.kind.rawValue, privacy: .public)")
        }
    }

    private func dismissPeek() {
        guard state.peek != nil else { return }
        state.peek = nil
        Log.peek.info("peek dismissed")
    }

    /// Spike 3 `growThenAnimate`: turning live on grows the frame first, then animates the
    /// wings in; turning it off snaps the wings out, then shrinks the frame.
    private func applyIdleGeometry(animated: Bool) {
        guard panel != nil else { return } // `place` applies it once the panel exists
        if desiredLive && !state.live {
            setPanelFrame(.idle, live: true)
            if animated {
                withAnimation(Self.spring) { state.live = true }
            } else {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { state.live = true }
            }
            refreshHotRect()
        } else if !desiredLive && state.live {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { state.live = false }
            setPanelFrame(.idle, live: false)
        } else {
            setPanelFrame(.idle, live: state.live)
        }
    }

    private func setPanelFrame(_ kind: FrameKind, live: Bool) {
        let frame = switch kind {
        case .idle, .expanded:
            IslandLayout.panelFrame(notch: notch, live: live, expanded: kind == .expanded)
        case .peek:
            IslandLayout.peekPanelFrame(notch: notch)
        }
        // Settle the new container before starting the shape's spring. Otherwise
        // SwiftUI can animate the pending resize/recentering along with the shape,
        // making an opening look like it sweeps sideways from the old narrow frame.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            panel?.setFrame(frame, display: false, animate: false)
            trackingView.layoutSubtreeIfNeeded()
            hostingView.layoutSubtreeIfNeeded()
        }
        Log.layout.info("frame \(kind.rawValue, privacy: .public) x=\(frame.minX, format: .fixed(precision: 1), privacy: .public) y=\(frame.minY, format: .fixed(precision: 1), privacy: .public) w=\(frame.width, format: .fixed(precision: 1), privacy: .public) h=\(frame.height, format: .fixed(precision: 1), privacy: .public) live=\(live, privacy: .public)")
        refreshHotRect()
    }

    /// The idle hot rect follows the TARGET live flag (Spike 3), so a new wing is hoverable at once.
    private func refreshHotRect() {
        trackingView.hotRect = IslandLayout.hotRect(region, notch: notch, live: desiredLive, panelFrame: panel?.frame ?? .zero)
    }
}
