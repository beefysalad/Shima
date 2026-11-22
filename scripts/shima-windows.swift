import AppKit
import CoreGraphics

// Independent alignment measurement: compares the notch (from NSScreen) with Shima's real
// on-screen island window (from the window server). All rects are in top-left CG coordinates.

struct R { var x, y, w, h: Double }

func fmt(_ r: R) -> String { "x=\(Int(r.x.rounded())) y=\(Int(r.y.rounded())) w=\(Int(r.w.rounded())) h=\(Int(r.h.rounded()))" }

let screens = NSScreen.screens
guard let primary = screens.first,
      let builtIn = screens.first(where: {
          guard let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
          else { return false }
          return CGDisplayIsBuiltin(id) != 0
      })
else { print("no built-in display"); exit(2) }

let flipY = primary.frame.maxY
let f = builtIn.frame
let inset = builtIn.safeAreaInsets.top
var notch: R
if inset > 0, let l = builtIn.auxiliaryTopLeftArea, let r = builtIn.auxiliaryTopRightArea, r.minX > l.maxX {
    notch = R(x: l.maxX, y: flipY - f.maxY, w: r.minX - l.maxX, h: inset)
} else {
    notch = R(x: f.midX - 100, y: flipY - f.maxY, w: 200, h: 32)
}
let mode = CommandLine.arguments.dropFirst().first ?? ""
print("built-in \(Int(f.width))x\(Int(f.height)) notch \(fmt(notch))")

let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []

func rectOf(_ w: [String: Any]) -> R? {
    guard let b = w[kCGWindowBounds as String] as? [String: Double],
          let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"] else { return nil }
    return R(x: x, y: y, w: width, h: height)
}

if mode == "--menus" {
    var found = 0
    for w in info {
        let owner = (w[kCGWindowOwnerName as String] as? String) ?? "?"
        let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
        guard owner != "Shima", layer >= 101, let r = rectOf(w) else { continue }
        print("menu window owner=\(owner) \(fmt(r))")
        found += 1
    }
    if found == 0 { print("no menu window"); exit(1) }
    exit(0)
}

var best: (layer: Int, rect: R)?
for w in info where (w[kCGWindowOwnerName as String] as? String) == "Shima" {
    guard let r = rectOf(w), abs(r.y) < 0.5 else { continue }
    let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
    if best == nil || abs((r.x + r.w / 2) - (notch.x + notch.w / 2))
        < abs((best!.rect.x + best!.rect.w / 2) - (notch.x + notch.w / 2)) {
        best = (layer, r)
    }
}
guard let island = best else { print("no island window"); exit(2) }
print("window layer=\(island.layer) \(fmt(island.rect))")

var expected = notch
var okMessage = "PASS idle frame matches notch within 1pt"
switch mode {
case "--live", "--live-frame-only":
    expected = R(x: notch.x - 33, y: notch.y, w: notch.w + 66, h: notch.h)
    okMessage = "PASS live frame matches notch+wings within 1pt"
case "--expanded":
    expected = R(x: notch.x + notch.w / 2 - 198, y: notch.y, w: 396, h: 173)
    okMessage = "PASS expanded frame matches layout within 1pt"
case "": break
default: print("unknown mode \(mode)"); exit(2)
}

let r = island.rect
let ok = abs(r.x - expected.x) <= 1 && abs(r.y - expected.y) <= 1
    && abs((r.x + r.w) - (expected.x + expected.w)) <= 1 && abs((r.y + r.h) - (expected.y + expected.h)) <= 1
guard ok else {
    print("MISMATCH expected \(fmt(expected)) window \(fmt(r))")
    exit(1)
}
print(okMessage)
if mode == "--live-frame-only" { exit(0) }

if mode == "--live" {  // --live-frame-only stops above: frame check only, no status item lookup
    // First status item: leftmost non-Shima window at layer 25, y == 0, right of the notch.
    var first: R?
    for w in info {
        let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
        let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
        guard owner != "Shima", layer == 25, let sr = rectOf(w), abs(sr.y) < 0.5, sr.x >= notch.x + notch.w else { continue }
        if first == nil || sr.x < first!.x { first = sr }
    }
    guard let item = first else { print("no status item found"); exit(2) }
    print("first status item x=\(Int(item.x.rounded()))")
    let gap = item.x - (r.x + r.w)
    if gap >= 0 {
        print("PASS wings clear first status item (gap \(Int(gap.rounded()))pt)")
    } else if gap >= -8 {
        // Status item windows include padding, so a small overlap is not a real collision.
        print("WARN wings overlap first status item by \(Int((-gap).rounded()))pt (item windows include padding; check by eye)")
    } else {
        print("FAIL wings overlap first status item by \(Int((-gap).rounded()))pt")
        exit(1)
    }
}
