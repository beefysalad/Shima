import AppKit
import SwiftUI
import ShimaCore

/// The device banner as drawn in mockup/index.html: a round badge with the device's SF Symbol, "Connected" over the
/// device name, and the battery level on the right when the system reports one. Geometry is `PeekLayout`. The overlay
/// never takes hits, so hovering the banner reaches the hover machine and opens the island.
struct PeekContent: View {
    let state: AppState

    private let ink2 = Color.white.opacity(0.62)
    private let low = Color(red: 1, green: 0.412, blue: 0.38)

    var body: some View {
        let showing = state.mode == .peek
        ZStack(alignment: .topLeading) {
            if let item = state.peek {
                switch item {
                case .device(let device): deviceBanner(device)
                }
            }
        }
        .frame(width: IslandLayout.peek.width, height: IslandLayout.peek.height, alignment: .topLeading)
        .opacity(showing ? 1 : 0)
        .animation(.easeOut(duration: 0.18).delay(showing ? 0.08 : 0), value: showing)
        .allowsHitTesting(false)
    }

    private func deviceBanner(_ device: DevicePeek) -> AnyView {
        let percent = device.batteryText.flatMap { Int($0.dropLast()) }
        if device.batteryText == nil { return AnyView(centeredBanner(device)) }
        let subtitleRect = PeekLayout.subtitle
        return AnyView(ZStack(alignment: .topLeading) {
            Circle().fill(Color.white.opacity(0.13))
                .overlay(Image(systemName: Self.symbolName(for: device.kind))
                    .font(.system(size: PeekLayout.glyphSize, weight: .medium)).foregroundStyle(.white))
                .frame(width: PeekLayout.badge.width, height: PeekLayout.badge.height)
                .position(x: PeekLayout.badge.midX, y: PeekLayout.badge.midY)
            Text(device.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                .frame(width: PeekLayout.title.width, height: PeekLayout.title.height, alignment: .leading)
                .position(x: PeekLayout.title.midX, y: PeekLayout.title.midY)
            Text(device.subtitle).font(.system(size: 11.5)).foregroundStyle(ink2).lineLimit(1).truncationMode(.tail)
                .frame(width: subtitleRect.width, height: subtitleRect.height, alignment: .leading)
                .position(x: subtitleRect.midX, y: subtitleRect.midY)
            if let text = device.batteryText {
                battery(text: text, percent: percent)
                    .frame(width: PeekLayout.batteryGroup.width, height: PeekLayout.batteryGroup.height, alignment: .trailing)
                    .position(x: PeekLayout.batteryGroup.midX, y: PeekLayout.batteryGroup.midY)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.title), \(device.subtitle)" + (device.batteryText.map { ", battery \($0)" } ?? "")))
    }

    /// No battery to balance the row, so badge and text sit as one group centred under the notch.
    private func centeredBanner(_ device: DevicePeek) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Color.white.opacity(0.13))
                .overlay(Image(systemName: Self.symbolName(for: device.kind))
                    .font(.system(size: PeekLayout.glyphSize, weight: .medium)).foregroundStyle(.white))
                .frame(width: PeekLayout.badge.width, height: PeekLayout.badge.height)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(device.subtitle).font(.system(size: 11.5)).foregroundStyle(ink2).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: 256, alignment: .leading)
        }
        .frame(width: IslandLayout.peek.width, height: IslandLayout.peek.height - 32, alignment: .center)
        .offset(y: 32 - 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.title), \(device.subtitle)")
    }

    private func battery(text: String, percent: Int?) -> some View {
        let isLow = (percent ?? 100) <= PeekLayout.lowBattery
        let color = isLow ? low : ink2
        let fill = CGFloat(min(max(percent ?? 0, 0), 100)) / 100
        return HStack(spacing: PeekLayout.batteryGap) {
            Text(text).font(.system(size: 11.5, weight: .semibold)).monospacedDigit().foregroundStyle(color).lineLimit(1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).strokeBorder(color.opacity(0.5), lineWidth: 0.9)
                RoundedRectangle(cornerRadius: 1.6).fill(isLow ? low : Color.white.opacity(0.8))
                    .frame(width: 15 * fill, height: 6.5).padding(.leading, 1.8)
            }
            .frame(width: PeekLayout.batteryGlyph.width - 1.6, height: PeekLayout.batteryGlyph.height)
            .overlay(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 0.8).fill(color.opacity(0.5)).frame(width: 1.6, height: 4).offset(x: 2.4)
            }
        }
    }

    /// The SF Symbol for a kind; AirPods fall back to the older glyph, anything unknown to the generic one.
    static func symbolName(for kind: DeviceKind) -> String {
        let preferred = kind.symbolName
        if NSImage(systemSymbolName: preferred, accessibilityDescription: nil) != nil { return preferred }
        if kind == .earbuds, NSImage(systemSymbolName: "airpods", accessibilityDescription: nil) != nil { return "airpods" }
        return DeviceKind.other.symbolName
    }
}
