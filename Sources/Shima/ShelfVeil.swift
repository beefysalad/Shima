import SwiftUI
import ShimaCore

/// The drag veil from mockup/index.html: black over the content area below the header strip, one Shelf tile
/// (blue while the cursor is over it, dimmed when the shelf is full) and an "n of 20" line.
/// Island-sized overlay with explicit frames; geometry is `ShelfLayout`. Never hit-tested (the drop
/// destination is the AppKit view underneath).
struct ShelfVeil: View {
    let count: Int
    let isFull: Bool
    let overTile: Bool

    private let fill = Color.white.opacity(0.075)
    private let ink2 = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.62)
    private let ink3 = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.52)
    private let done = Color(red: 134 / 255, green: 174 / 255, blue: 247 / 255)

    var body: some View {
        let over = overTile && !isFull
        let tile = ShelfLayout.veilTile
        ZStack(alignment: .topLeading) {
            Color.black
                .frame(width: ShelfLayout.veil.width, height: ShelfLayout.veil.height)
                .position(x: ShelfLayout.veil.midX, y: ShelfLayout.veil.midY)
            RoundedRectangle(cornerRadius: ShelfLayout.veilTileRadius)
                .fill(over ? done.opacity(0.25) : fill)
                .overlay(RoundedRectangle(cornerRadius: ShelfLayout.veilTileRadius)
                    .strokeBorder(over ? done : Color.clear, lineWidth: 1))
                .opacity(isFull ? 0.5 : 1)
                .frame(width: tile.width, height: tile.height)
                .position(x: tile.midX, y: tile.midY)
            FolderGlyph()
                .stroke(over ? done : (isFull ? ink3 : ink2), style: StrokeStyle(lineWidth: 1.5 * ShelfLayout.veilIcon.width / 24, lineCap: .round, lineJoin: .round))
                .opacity(isFull ? 0.5 : 1)
                .frame(width: ShelfLayout.veilIcon.width, height: ShelfLayout.veilIcon.height)
                .position(x: ShelfLayout.veilIcon.midX, y: ShelfLayout.veilIcon.midY)
            Text(isFull ? ShelfText.veilCaptionFull : ShelfText.veilCaption)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(over ? done : ink3)
                .opacity(isFull ? 0.5 : 1)
                .frame(width: ShelfLayout.veilCaption.width, height: ShelfLayout.veilCaption.height)
                .position(x: ShelfLayout.veilCaption.midX, y: ShelfLayout.veilCaption.midY)
            Text(ShelfText.veilCount(count))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(ink3)
                .frame(width: ShelfLayout.veilCount.width, height: ShelfLayout.veilCount.height)
                .position(x: ShelfLayout.veilCount.midX, y: ShelfLayout.veilCount.midY)
        }
        .frame(width: IslandLayout.expanded.width, height: IslandLayout.expanded.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// The mockup's folder outline (24-unit viewBox): M3 7.5A2.5 2.5 0 0 1 5.5 5H9l2 2.5h7.5A2.5 2.5 0 0 1 21 10v7.5a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 17.5Z
struct FolderGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        path.move(to: p(3, 7.5))
        path.addQuadCurve(to: p(5.5, 5), control: p(3, 5))
        path.addLine(to: p(9, 5)); path.addLine(to: p(11, 7.5)); path.addLine(to: p(18.5, 7.5))
        path.addQuadCurve(to: p(21, 10), control: p(21, 7.5))
        path.addLine(to: p(21, 17.5))
        path.addQuadCurve(to: p(18.5, 20), control: p(21, 20))
        path.addLine(to: p(5.5, 20))
        path.addQuadCurve(to: p(3, 17.5), control: p(3, 20))
        path.closeSubpath()
        return path
    }
}
