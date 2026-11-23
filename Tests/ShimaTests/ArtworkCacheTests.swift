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

private final class ArtworkHTTPProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        if url.lastPathComponent == "transport-error" {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        do {
            let data = url.lastPathComponent == "malformed" ? Data("not an image".utf8) : try artworkPNG()
            let response: URLResponse
            if url.lastPathComponent == "non-http" {
                response = URLResponse(url: url, mimeType: "image/png", expectedContentLength: data.count, textEncodingName: nil)
            } else {
                let finalURL = url.lastPathComponent == "insecure-final" ? URL(string: "http://artwork.example.test/image")! : url
                response = HTTPURLResponse(url: finalURL, statusCode: Int(url.lastPathComponent) ?? 200,
                                           httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

extension ArtworkCacheTests {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArtworkHTTPProtocol.self]
        return URLSession(configuration: configuration)
    }
    private func url(_ path: String) -> URL { URL(string: "https://artwork.example.test/\(path)")! }

    @Test func fetchAcceptsSuccessfulHTTPAndBoundsDecodedImageSize() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        for status in [200, 201, 299] {
            let image = try await ArtworkCache.fetch(url(String(status)), session: session)
            #expect(image.width == 176 && image.height == 88)
        }
    }

    @Test func fetchRejectsHTTPFailuresNonHTTPAndUnsafeFinalURLs() async {
        let session = session()
        defer { session.invalidateAndCancel() }
        for path in ["199", "300", "404", "503", "non-http", "insecure-final", "malformed"] {
            do {
                _ = try await ArtworkCache.fetch(url(path), session: session)
                Issue.record("Artwork response must be rejected: \(path)")
            } catch { #expect((error as? URLError)?.code == .cannotDecodeContentData) }
        }
    }

    @Test func fetchPropagatesTransportFailure() async {
        let session = session()
        defer { session.invalidateAndCancel() }
        do {
            _ = try await ArtworkCache.fetch(url("transport-error"), session: session)
            Issue.record("Transport failure must propagate")
        } catch { #expect((error as? URLError)?.code == .networkConnectionLost) }
    }

    @Test func fetchDoesNotReturnAnImageToACancelledTask() async {
        let session = session()
        defer { session.invalidateAndCancel() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ArtworkCache.fetch(url("200"), session: session)
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled fetch must not return an image")
        } catch {
            #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
    }

    private func redirect(_ request: URLRequest) async -> URLRequest? {
        let session = session()
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: url("200")) // Never resumed: the delegate test sends no requests.
        let response = HTTPURLResponse(url: url("redirect"), statusCode: 302, httpVersion: nil, headerFields: nil)!
        return await withCheckedContinuation { continuation in
            HTTPSArtworkRedirects().urlSession(session, task: task, willPerformHTTPRedirection: response,
                                              newRequest: request) { continuation.resume(returning: $0) }
        }
    }

    @Test func redirectDelegatePreservesAllowedHTTPSRequest() async {
        var request = URLRequest(url: URL(string: "https://cdn.example.test/image?size=large")!)
        request.setValue("fixture", forHTTPHeaderField: "X-Fixture")
        #expect(await redirect(request) == request)
    }

    @Test func redirectDelegateRejectsInsecureHostlessAndMissingURLs() async {
        for value in ["http://cdn.example.test/image", "file:///image", "https:/image"] {
            #expect(await redirect(URLRequest(url: URL(string: value)!)) == nil)
        }
        var missing = URLRequest(url: url("200"))
        missing.url = nil
        #expect(await redirect(missing) == nil)
    }
}
