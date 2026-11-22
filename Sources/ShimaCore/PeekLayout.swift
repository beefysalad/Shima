import CoreGraphics

/// Device banner geometry in the peek island's local, top-left coordinates (points). The island is
/// `IslandLayout.peek` (340 x 76); the top 32 pt strip overlays the notch and stays empty here.
/// Values come from the "Layout table" in docs/superpowers/specs/2026-11-23-device-popups-design.md
/// (approved mockup/index.html, "Bluetooth device connects").
public enum PeekLayout {
    public static let badge = CGRect(x: 22, y: 38, width: 30, height: 30)
    public static let glyphSize: CGFloat = 15
    public static let title = CGRect(x: 62, y: 39, width: 190, height: 16)
    /// Device name: one line, tail truncation; the wide rect is used when there is no battery.
    public static let subtitle = CGRect(x: 62, y: 56, width: 190, height: 14)
    public static let subtitleWide = CGRect(x: 62, y: 56, width: 256, height: 14)
    /// Battery text and glyph, right-aligned to x 318, vertically centred at y 55.
    public static let batteryGroup = CGRect(x: 252, y: 48, width: 66, height: 14)
    public static let batteryGlyph = CGSize(width: 20, height: 10)
    public static let batteryGap: CGFloat = 8
    /// At or below this percentage the battery text and fill turn red.
    public static let lowBattery = 15
}
