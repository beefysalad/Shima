import AppKit
import CoreGraphics
// Synthetic input for verification. Usage:
//   swift scripts/drive.swift "move 735 16; sleep 500; click 786.5 128; fake playing; key esc"
// Coordinates are global top-left CG points (as printed by scripts/shima-windows.swift).
// `fake CMD` posts the distributed notification local.shima.fake-spotify (object CMD), read only by shima in fake mode.
let start = Date()
func stamp(_ s: String) { print(String(format: "t=%6.0fms ", Date().timeIntervalSince(start) * 1000) + s); fflush(stdout) }
func mouse(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func wait(_ ms: Double) { RunLoop.current.run(until: Date().addingTimeInterval(ms / 1000)) }
for raw in CommandLine.arguments.dropFirst().joined(separator: ";").split(separator: ";") {
    let w = raw.split(separator: " ").map(String.init)
    guard let op = w.first else { continue }
    let n = w.dropFirst().compactMap(Double.init)
    stamp(w.joined(separator: " "))
    switch op {
    case "move": mouse(.mouseMoved, CGPoint(x: n[0], y: n[1]))
    case "click":
        let p = CGPoint(x: n[0], y: n[1])
        mouse(.mouseMoved, p); wait(150); mouse(.leftMouseDown, p); wait(60); mouse(.leftMouseUp, p)
    case "sleep": wait(n[0])
    case "key" where w.count > 1 && w[1] == "esc":
        for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap) }
    case "fake" where w.count > 1:
        DistributedNotificationCenter.default().postNotificationName(
            .init("local.shima.fake-spotify"), object: w[1], userInfo: nil, deliverImmediately: true)
        wait(5)
    default: stamp("unknown step: \(w.joined(separator: " "))"); exit(2)
    }
}
