// Run from the repository root: swift assets/branding/generate.swift
// CoreText is used only when regenerating; exported SVG lettering is outlined.
import Foundation
import CoreText
import CoreGraphics

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("assets/branding")
func number(_ value: CGFloat) -> String { String(format: "%.3f", Double(value)) }
func lettering(_ text: String, fontName: String, size: CGFloat) -> (String, CGFloat) {
    let font = CTFontCreateWithName(fontName as CFString, size, nil)
    let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
    let line = CTLineCreateWithAttributedString(attributed)
    var output = ""
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
        for index in 0..<count {
            guard let path = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
            var d = ""
            func point(_ p: CGPoint) -> String { "\(number(p.x + positions[index].x)) \(number(-p.y))" }
            path.applyWithBlock { element in
                let e = element.pointee
                switch e.type {
                case .moveToPoint: d += "M" + point(e.points[0])
                case .addLineToPoint: d += "L" + point(e.points[0])
                case .addQuadCurveToPoint: d += "Q" + point(e.points[0]) + " " + point(e.points[1])
                case .addCurveToPoint: d += "C" + point(e.points[0]) + " " + point(e.points[1]) + " " + point(e.points[2])
                case .closeSubpath: d += "Z"
                @unknown default: break
                }
            }
            output += "<path d=\"\(d)\"/>"
        }
    }
    return (output, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
}

// Canonical split-current S: two opposing ribbons on a 160 × 160 grid.
// A half-turn pairs the curves and leaves a diagonal channel of negative space.
let ribbon = "M140 16H69C37 16 16 34 16 60C16 83 34 98 60 98H67L93 72H61C49 72 42 67 42 58C42 48 52 42 68 42H114Z"
let mark = "<path d=\"\(ribbon)\" transform=\"translate(-3 -15)\"/><path d=\"\(ribbon)\" transform=\"translate(163 175) rotate(180)\"/>"
func svg(_ title: String, box: String, body: String) -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(box)\" role=\"img\" aria-labelledby=\"title\"><title id=\"title\">\(title)</title>\(body)</svg>\n"
}
func save(_ name: String, _ contents: String) throws {
    try contents.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
}
let (word, wordWidth) = lettering("shima", fontName: "AvenirNext-DemiBold", size: 76)
let (byline, bylineWidth) = lettering("by Patrick", fontName: "Menlo-Regular", size: 12)
for light in [false, true] {
    let suffix = light ? "-light" : ""
    let bg = light ? "#fff8f1" : "#000000"
    let ink = light ? "#24201d" : "#f5f0eb"
    let small = light ? "#73665c" : "#b5a99f"
    let symbol = "<g id=\"mark\" fill=\"#ff6500\" transform=\"translate(24 22) scale(.8)\">\(mark)</g>"
    let name = "<g id=\"word\" fill=\"\(ink)\" transform=\"translate(190 113)\">\(word)</g>"
    let bylineX = number(190 + (wordWidth - bylineWidth) / 2)
    let credit = "<g id=\"byline\" fill=\"\(small)\" transform=\"translate(\(bylineX) 145)\">\(byline)</g>"
    try save("shima-logo\(suffix).svg", svg("shima by Patrick", box: "0 0 470 176", body: "<path fill=\"\(bg)\" d=\"M0 0H470V176H0Z\"/>" + symbol + name + credit))
}
try save("shima-mark.svg", svg("Shima split-current S mark", box: "0 0 160 160", body: "<g fill=\"#ff6500\">\(mark)</g>"))
try save("shima-lockup.svg", svg("shima", box: "0 0 470 144", body: "<path fill=\"#000000\" d=\"M0 0H470V144H0Z\"/><g fill=\"#ff6500\" transform=\"translate(24 8) scale(.8)\">\(mark)</g><g fill=\"#f5f0eb\" transform=\"translate(190 97)\">\(word)</g>"))
let tile = "<rect width=\"256\" height=\"256\" rx=\"56\" fill=\"#000000\"/><rect x=\"0.5\" y=\"0.5\" width=\"255\" height=\"255\" rx=\"55.5\" fill=\"none\" stroke=\"#ffffff\" stroke-opacity=\".10\"/><g fill=\"#ff6500\" transform=\"translate(36 36) scale(1.15)\">\(mark)</g>"
try save("shima-icon.svg", svg("Shima app icon", box: "0 0 256 256", body: tile))
try save("shima-app-icon-macos.svg", svg("Shima macOS app icon", box: "0 0 1024 1024", body: "<g transform=\"translate(100 100) scale(3.21875)\">\(tile)</g>"))
