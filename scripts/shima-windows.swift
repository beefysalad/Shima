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
print("built-in \(Int(f.width))x\(Int(f.height)) notch \(fmt(notch))")

let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
var best: (layer: Int, rect: R)?
for w in info where (w[kCGWindowOwnerName as String] as? String) == "Shima" {
    guard let b = w[kCGWindowBounds as String] as? [String: Double],
          let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
          abs(y) < 0.5 else { continue }
    let rect = R(x: x, y: y, w: width, h: height)
    let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
    if best == nil || abs((rect.x + rect.w / 2) - (notch.x + notch.w / 2))
        < abs((best!.rect.x + best!.rect.w / 2) - (notch.x + notch.w / 2)) {
        best = (layer, rect)
    }
}
guard let island = best else { print("no island window"); exit(2) }
print("window layer=\(island.layer) \(fmt(island.rect))")

let r = island.rect
let ok = abs(r.x - notch.x) <= 1 && abs(r.y - notch.y) <= 1
    && abs((r.x + r.w) - (notch.x + notch.w)) <= 1 && abs((r.y + r.h) - (notch.y + notch.h)) <= 1
if ok {
    print("PASS idle frame matches notch within 1pt")
} else {
    print("MISMATCH notch \(fmt(notch)) window \(fmt(r))")
    exit(1)
}
