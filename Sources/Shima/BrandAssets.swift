import SwiftUI
import ImageIO

/// Original brand artwork, packaged locally; never substitutes an SF Symbol for a logo.
@MainActor enum BrandAssets {
    private static var images: [String: NSImage] = [:]
    static func image(_ name: String) -> NSImage {
        if let image = images[name] { return image }
        // The largest brand mark is 64 pt. Decode at 2x once rather than retaining
        // 940 px Spotify bitmaps for 12–28 pt controls across tab updates.
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 128,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            preconditionFailure("Missing bundled brand asset: \(name).png")
        }
        let image = NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
        images[name] = image
        return image
    }
}

struct BrandLogo: View {
    let name: String
    var body: some View {
        Image(nsImage: BrandAssets.image(name))
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}
