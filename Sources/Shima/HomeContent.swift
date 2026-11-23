import SwiftUI
import ShimaCore

/// The Home tab as drawn in mockup/index.html: a row of shelf chips (or the empty state), a count and Clear.
/// Geometry is `ShelfLayout`. Mounted as an island-sized overlay only while Home is open, so it never changes
/// the root layout and nothing here runs while the island is closed.
struct HomeContent: View {
    let shelf: ShelfStore
    /// Transient status line ("Added 3"); set by the drop handling, nil here.
    var status: (text: String, warn: Bool)? = nil

    private let fill = Color.white.opacity(0.075)
    private let fill2 = Color.white.opacity(0.13)
    private let ink = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    private let ink2 = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.62)
    private let ink3 = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.52)
    private let done = Color(red: 134 / 255, green: 174 / 255, blue: 247 / 255)
    private let claude = Color(red: 224 / 255, green: 122 / 255, blue: 79 / 255)

    var body: some View {
        let items = shelf.items
        ZStack(alignment: .topLeading) {
            if items.isEmpty {
                Text(ShelfText.emptyState)
                    .font(.system(size: 12.5))
                    .foregroundStyle(ink3)
                    .multilineTextAlignment(.center)
                    .frame(width: ShelfLayout.emptyState.width, height: ShelfLayout.emptyState.height)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    .position(x: ShelfLayout.emptyState.midX, y: ShelfLayout.emptyState.midY)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ShelfLayout.chipGap) {
                        ForEach(items) { item in chip(item) }
                    }
                }
                .frame(width: ShelfLayout.chipRow.width, height: ShelfLayout.chipRow.height)
                .position(x: ShelfLayout.chipRow.midX, y: ShelfLayout.chipRow.midY)
            }
            if let status {
                Text(status.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(status.warn ? claude : done)
                    .frame(width: ShelfLayout.statusLine.width, height: ShelfLayout.statusLine.height, alignment: .leading)
                    .position(x: ShelfLayout.statusLine.midX, y: ShelfLayout.statusLine.midY)
            }
            Text(ShelfText.homeCount(items.count))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(ink3)
                .frame(width: ShelfLayout.countLabel.width, height: ShelfLayout.countLabel.height, alignment: .leading)
                .position(x: ShelfLayout.countLabel.midX, y: ShelfLayout.countLabel.midY)
            Button { shelf.clear() } label: {
                Text(ShelfText.clear)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: ShelfLayout.clearButton.width, height: ShelfLayout.clearButton.height)
                    .background(RoundedRectangle(cornerRadius: 9).fill(fill2))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(items.isEmpty)
            .opacity(items.isEmpty ? 0.4 : 1)
            .position(x: ShelfLayout.clearButton.midX, y: ShelfLayout.clearButton.midY)
        }
        .frame(width: IslandLayout.expanded.width, height: IslandLayout.expanded.height, alignment: .topLeading)
    }

    /// Mockup chip proportions fitted to the 116 x 64 pt chip: badge 24 x 26, name and sub-line stacked beneath.
    private func chip(_ item: ShelfItem) -> some View {
        VStack(spacing: 3) {
            Text(ShelfText.badge(item))
                .font(.system(size: 7, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.black.opacity(0.65))
                .padding(.bottom, 3)
                .frame(width: 24, height: 26, alignment: .bottom)
                .background(RoundedRectangle(cornerRadius: 4).fill(Self.badgeColor(ShelfText.badge(item))))
            VStack(spacing: 0) {
                Text(item.name).font(.system(size: 10.5, weight: .medium)).foregroundStyle(ink).frame(height: 13)
                Text(ShelfText.subline(item, fileSize: Self.fileSize(item))).font(.system(size: 9.5)).foregroundStyle(ink3).frame(height: 12)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(width: ShelfLayout.chipSize.width, height: ShelfLayout.chipSize.height)
        .background(RoundedRectangle(cornerRadius: ShelfLayout.chipRadius).fill(fill))
        .overlay(alignment: .topLeading) {
            let x = ShelfLayout.chipRemove(chipX: 0, chipY: 0)
            Button { shelf.remove(id: item.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(ink2)
                    .frame(width: x.width, height: x.height)
                    .background(Circle().fill(fill2))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(ShelfText.remove) \(item.name)")
            .help(ShelfText.remove)
            .offset(x: x.minX, y: x.minY)
        }
        .help(item.name)
    }

    /// The mockup's `EXT_COLOR`; anything else is the neutral grey.
    static func badgeColor(_ badge: String) -> Color {
        func hex(_ v: UInt32) -> Color {
            Color(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
        }
        switch badge {
        case "png", "jpg", "jpeg", "gif", "heic": return hex(0x7fd3c4)
        case "pdf": return hex(0xff8a80)
        case "toml", "json": return hex(0xf2c66d)
        case "zip": return hex(0xd7b48a)
        case "swift", "swif": return hex(0xff9e6b)
        case "mov", "mp4": return hex(0xb39dff)
        case "link": return hex(0x86AEF7)
        default: return hex(0xc8ccd2)
        }
    }

    private static func fileSize(_ item: ShelfItem) -> Int? {
        guard case .file(let url) = item.kind else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
    }
}
