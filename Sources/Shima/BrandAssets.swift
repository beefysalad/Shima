import SwiftUI

/// Original brand artwork, packaged locally; never substitutes an SF Symbol for a logo.
enum BrandAssets {
    static func image(_ name: String) -> NSImage {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing bundled brand asset: \(name).png")
        }
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
