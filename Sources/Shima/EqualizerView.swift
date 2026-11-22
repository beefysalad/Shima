import AppKit
import SwiftUI
import os

/// Four-bar equalizer drawn with Core Animation. Animations exist only while `animating` is true
/// and the window is visible; otherwise they are removed so the layer tree is static (design doc 8.4).
final class EqualizerNSView: NSView {
    static var tint = NSColor(srgbRed: 0x1E / 255, green: 0xD7 / 255, blue: 0x60 / 255, alpha: 1)
    /// Frame rate for the bar animations; `nil` = display rate. Spike 5: no rate met the budget; 20 kept (see notes).
    static var frameRate: Float? = 20

    private static let log = Logger(subsystem: "local.shima", category: "eq")
    private static let barWidth: CGFloat = 2.5
    private static let barHeight: CGFloat = 14
    private static let gap: CGFloat = 2
    private static let durations: [CFTimeInterval] = [0.9, 0.7, 1.1, 0.8]
    private static let offsets: [CFTimeInterval] = [0, 0.3, 0.5, 0.2]
    private static let restTransform = CATransform3DMakeScale(1, 0.25, 1)

    private var bars: [CALayer] = []
    private var isRunning = false
    private var occlusionObserver: NSObjectProtocol?

    var animating: Bool = false { didSet { apply() } }

    override init(frame: NSRect) { super.init(frame: frame); setUp() }
    required init?(coder: NSCoder) { super.init(coder: coder); setUp() }

    private func setUp() {
        wantsLayer = true
        for i in 0..<4 {
            let bar = CALayer()
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.barHeight)
            bar.cornerRadius = Self.barWidth / 2
            bar.backgroundColor = Self.tint.cgColor
            bar.transform = Self.restTransform
            layer?.addSublayer(bar)
            bars.append(bar)
            _ = i
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 4 * Self.barWidth + 3 * Self.gap, height: Self.barHeight)
    }

    override func layout() {
        super.layout()
        let total = 4 * Self.barWidth + 3 * Self.gap
        let x0 = (bounds.width - total) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.position = CGPoint(x: x0 + Self.barWidth / 2 + CGFloat(i) * (Self.barWidth + Self.gap),
                                   y: bounds.midY)
        }
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let o = occlusionObserver { NotificationCenter.default.removeObserver(o); occlusionObserver = nil }
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.apply() } }
        }
        apply()
    }

    private func apply() {
        let effective = animating && (window?.occlusionState.contains(.visible) ?? false)
        guard effective != isRunning else { return }
        isRunning = effective
        if effective {
            for (i, bar) in bars.enumerated() where bar.animation(forKey: "eq") == nil {
                let a = CABasicAnimation(keyPath: "transform.scale.y")
                a.fromValue = 0.22
                a.toValue = 1.0
                a.autoreverses = true
                a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                a.duration = Self.durations[i]
                a.timeOffset = Self.offsets[i]
                a.isRemovedOnCompletion = false
                if let r = Self.frameRate {
                    a.preferredFrameRateRange = CAFrameRateRange(minimum: r, maximum: r, preferred: r)
                }
                bar.add(a, forKey: "eq")
            }
            let n = bars.reduce(0) { $0 + ($1.animationKeys()?.count ?? 0) }
            Self.log.debug("eq animating anims=\(n)")
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for bar in bars {
                bar.removeAnimation(forKey: "eq")
                bar.transform = Self.restTransform
            }
            CATransaction.commit()
            Self.log.debug("eq frozen anims=0")
        }
    }
}

struct EqualizerView: NSViewRepresentable {
    let animating: Bool
    func makeNSView(context: Context) -> EqualizerNSView {
        let v = EqualizerNSView(frame: .zero)
        v.animating = animating
        return v
    }
    func updateNSView(_ nsView: EqualizerNSView, context: Context) { nsView.animating = animating }
}
