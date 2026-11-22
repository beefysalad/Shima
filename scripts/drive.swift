import AppKit
import CoreGraphics
// Synthetic input for verification. Usage:
//   swift scripts/drive.swift "move 735 16; sleep 500; click 733.5 171; fake playing; key esc"
// `click-owned PID X Y` checks the topmost window at the point before posting a click.
// Keys: esc tab space return cmd-w cmd-comma (down, 20 ms, up). An unknown key exits 2.
// Coordinates are global top-left CG points (as printed by scripts/shima-windows.swift).
// `fake-calendar CMD` posts local.shima.fake-calendar (object CMD) for the fake Calendar service.
// `fake CMD` posts the distributed notification local.shima.fake-spotify (object CMD), read only by shima in fake mode.
// `fake-device connect|<name>|<kind>|<battery or ->` posts local.shima.fake-device, read only with SHIMA_FAKE_DEVICES=1.
let start = Date()
func stamp(_ s: String) { print(String(format: "t=%6.0fms ", Date().timeIntervalSince(start) * 1000) + s); fflush(stdout) }
func mouse(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func clickOwned(pid: pid_t, at point: CGPoint) {
    mouse(.mouseMoved, point)
    wait(150)
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
        stamp("Could not create guarded click"); exit(2)
    }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    let top = windows.first { window in
        guard (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
        return rect.contains(point)
    }
    let owner = top?[kCGWindowOwnerPID as String] as? pid_t
    let layer = top?[kCGWindowLayer as String] as? Int
    guard owner == pid, layer == Int(CGWindowLevelForKey(.statusWindow)),
          top?[kCGWindowOwnerName as String] as? String == "Shima" else {
        let name = top?[kCGWindowOwnerName as String] as? String ?? "unknown"
        stamp("Refusing click at \(point): topmost window is \(name) PID \(owner ?? 0), expected Shima island PID \(pid)")
        exit(2)
    }
    // Submit the pair together so the ownership check immediately precedes both events.
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
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
    case "click-owned":
        guard w.count == 4, let pid = pid_t(w[1]), pid > 0,
              let x = Double(w[2]), x.isFinite, let y = Double(w[3]), y.isFinite else {
            stamp("click-owned requires PID X Y"); exit(2)
        }
        clickOwned(pid: pid, at: CGPoint(x: x, y: y))
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
    case "fake-calendar" where w.count > 1:
        DistributedNotificationCenter.default().postNotificationName(
            .init("local.shima.fake-calendar"), object: w[1], userInfo: nil, deliverImmediately: true)
        wait(5)
    case "fake" where w.count > 1:
        DistributedNotificationCenter.default().postNotificationName(
            .init("local.shima.fake-spotify"), object: w[1], userInfo: nil, deliverImmediately: true)
        wait(5)
    case "fake-device" where w.count > 1:
        // Payload "connect|<name>|<kind>|<battery or ->" may contain spaces; it is everything after the step name.
        DistributedNotificationCenter.default().postNotificationName(
            .init("local.shima.fake-device"), object: w.dropFirst().joined(separator: " "), userInfo: nil, deliverImmediately: true)
        wait(5)
    default: stamp("unknown step: \(w.joined(separator: " "))"); exit(2)
    }
}
