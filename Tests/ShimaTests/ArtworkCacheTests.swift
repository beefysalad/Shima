import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Shima

private func artworkPNG(width: Int = 512, height: Int = 256) throws -> Data {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    return data as Data
}

struct ArtworkCacheTests {
    @Test func downsamplingBoundsPixelsAndPreservesAspectRatio() throws {
        let data = try artworkPNG()
        let standard = try #require(ArtworkCache.downsample(data))
        #expect(standard.width == 176 && standard.height == 88)
        let smaller = try #require(ArtworkCache.downsample(data, maxPixel: 40))
        #expect(smaller.width == 40 && smaller.height == 20)
        let portrait = try #require(ArtworkCache.downsample(artworkPNG(width: 256, height: 512)))
        #expect(portrait.width == 88 && portrait.height == 176)
    }

    @Test func downsamplingRejectsInvalidBoundsAndNonImageData() throws {
        let data = try artworkPNG()
        #expect(ArtworkCache.downsample(data, maxPixel: 0) == nil)
        #expect(ArtworkCache.downsample(data, maxPixel: -1) == nil)
        #expect(ArtworkCache.downsample(Data()) == nil)
        #expect(ArtworkCache.downsample(Data("not an image".utf8)) == nil)
    }
}
