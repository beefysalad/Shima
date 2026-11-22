import AppKit
import CoreGraphics
// Synthetic input for verification. Usage:
//   swift scripts/drive.swift "move 735 16; sleep 500; click 733.5 171; fake playing; key esc"
// Keys: esc tab space return cmd-w cmd-comma (down, 20 ms, up). An unknown key exits 2.
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
    case "key" where w.count > 1:
        let keys: [String: (CGKeyCode, CGEventFlags)] = [
            "esc": (53, []), "tab": (48, []), "space": (49, []), "return": (36, []),
            "cmd-w": (13, .maskCommand), "cmd-comma": (43, .maskCommand)]
        guard let key = keys[w[1]] else { stamp("unknown key: \(w[1])"); exit(2) }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: key.0, keyDown: down)
            e?.flags = key.1
            e?.post(tap: .cghidEventTap)
            if down { wait(20) }
        }
    case "camera" where w.count > 1:
        let command: String
        if w[1] == "quit" {
            guard w.count == 3, Int32(w[2]) != nil else {
                stamp("camera quit requires the target app PID"); exit(2)
            }
            // The scoped object is deliberately not plain "quit": older fake
            // instances must also ignore this command rather than terminate.
            command = "quit:" + w[2]
        } else { command = w[1] }
        DistributedNotificationCenter.default().postNotificationName(
            .init("local.shima.fake-camera"), object: command, userInfo: nil, deliverImmediately: true)
        wait(5)
    case "fake" where w.count > 1:
        DistributedNotificationCenter.default().postNotificationName(
            .init("local.shima.fake-spotify"), object: w[1], userInfo: nil, deliverImmediately: true)
        wait(5)
    default: stamp("unknown step: \(w.joined(separator: " "))"); exit(2)
    }
}
