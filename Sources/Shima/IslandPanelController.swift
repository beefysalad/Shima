import AppKit
import SwiftUI
import ShimaCore

@MainActor
final class IslandPanelController {
    private static let debug = ProcessInfo.processInfo.environment["SHIMA_DEBUG"] != nil
    /// Spike 1: a fully transparent hot zone still receives tracking events.
    private static let hitOpacity: Double = 0
    private static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)

    private let panel: NotchPanel
    private let trackingView = HoverTrackingView()
    private let hostingView: NSHostingView<IslandView>
    private let state = AppState()
    private var hover: HoverController!
    private var notch: CGRect = .zero
    private var hasNotch = false
    private var region: HotRegion = .idle

    var phase: ShimaCore.HoverPhase{ hover.phase }

    init() {
        panel = NotchPanel(contentRect: .zero)
        hostingView = NSHostingView(rootView: IslandView(
            state: state, notch: .zero, hasNotch: false,
            debug: Self.debug, hitOpacity: Self.hitOpacity))
        hostingView.frame = trackingView.bounds
        hostingView.autoresizingMask = [.width, .height]
        trackingView.addSubview(hostingView)
        panel.contentView = trackingView

        hover = HoverController(scheduler: DispatchScheduler()) { [weak self] effect in
            self?.perform(effect)
        }
        hover.onPhaseChange = { from, to in
            Log.hover.debug("hover \(String(describing: from), privacy: .public) -> \(String(describing: to), privacy: .public)")
        }
        trackingView.onPointer = { [weak self] inside in
            self?.hover.pointer(inside: inside)
        }
    }

    func place(on display: DisplayDescriptor?) {
        guard let display else { return } // hidden-panel path is Task 10
        notch = display.notchRect
        hasNotch = display.hasNotch
        hostingView.rootView = IslandView(
            state: state, notch: notch, hasNotch: hasNotch,
            debug: Self.debug, hitOpacity: Self.hitOpacity)
        hover.reset()
        setPanelFrame(expanded: false)
        panel.orderFrontRegardless()
    }

    private func perform(_ effect: HoverEffect) {
        switch effect {
        case .growPanel:
            setPanelFrame(expanded: true)
        case .shrinkPanel:
            setPanelFrame(expanded: false)
        case .setHotRegion(let r):
            region = r
            refreshHotRect()
        case .animateExpand:
            withAnimation(Self.spring) { state.mode = .expanded }
        case .animateCollapse(let generation):
            withAnimation(Self.spring, completionCriteria: .removed) {
                state.mode = .collapsed
            } completion: { [weak self] in
                self?.hover.collapseFinished(generation: generation)
            }
        case .snapCollapsed:
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { state.mode = .collapsed }
        case .startTimer, .cancelTimer:
            break // consumed by HoverController
        }
    }

    private func setPanelFrame(expanded: Bool) {
        let frame = IslandLayout.panelFrame(notch: notch, expanded: expanded)
        panel.setFrame(frame, display: true)
        Log.layout.info("frame \(expanded ? "expanded" : "idle", privacy: .public) x=\(frame.minX, format: .fixed(precision: 1), privacy: .public) y=\(frame.minY, format: .fixed(precision: 1), privacy: .public) w=\(frame.width, format: .fixed(precision: 1), privacy: .public) h=\(frame.height, format: .fixed(precision: 1), privacy: .public)")
        refreshHotRect()
    }

    private func refreshHotRect() {
        trackingView.hotRect = IslandLayout.hotRect(region, notch: notch, panelFrame: panel.frame)
    }
}
