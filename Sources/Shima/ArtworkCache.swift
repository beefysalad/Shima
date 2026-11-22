import AppKit
import ImageIO
import ShimaCore

/// Artwork is the app's only network access. Nothing is persisted to disk.
@MainActor
final class ArtworkCache {
    private weak var media: IslandMedia?
    private let cache = NSCache<NSURL, NSImage>()
    private let session: URLSession
    private var task: Task<Void, Never>?
    private var gate = ArtworkRequestGate()

    init(media: IslandMedia) {
        self.media = media
        cache.countLimit = 10
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration, delegate: HTTPSArtworkRedirects(), delegateQueue: nil)
    }

    func show(trackID: String?, url: URL?) {
        let selection = gate.select(trackID: trackID, url: url)
        guard selection != .unchanged else { return }
        task?.cancel()
        task = nil
        media?.artwork = nil
        guard case let .load(ticket) = selection else {
            Log.artwork.debug("artwork none")
            return
        }
        if let image = cache.object(forKey: ticket.url as NSURL) {
            media?.artwork = image
            Log.artwork.debug("artwork cached")
            return
        }
        Log.artwork.debug("artwork load host=\(ticket.url.host ?? "", privacy: .public)")
        let started = ContinuousClock.now
        let session = session
        task = Task { [weak self] in
            do {
                let image = try await Self.fetch(ticket.url, session: session)
                guard let self else { return }
                guard !Task.isCancelled, self.gate.accepts(ticket) else {
                    Log.artwork.debug("artwork dropped stale")
                    return
                }
                let result = NSImage(cgImage: image, size: NSSize(width: 88, height: 88))
                self.cache.setObject(result, forKey: ticket.url as NSURL)
                self.media?.artwork = result
                self.task = nil
                let elapsed = started.duration(to: .now).components
                let ms = Int(elapsed.seconds) * 1_000 + Int(elapsed.attoseconds / 1_000_000_000_000_000)
                Log.artwork.debug("artwork loaded px=\(max(image.width, image.height)) ms=\(ms)")
            } catch {
                guard let self else { return }
                guard !Task.isCancelled, self.gate.accepts(ticket) else {
                    Log.artwork.debug("artwork dropped stale")
                    return
                }
                self.gate.failed(ticket)
                self.media?.artwork = nil
                self.task = nil
                Log.artwork.debug("artwork failed code=\((error as NSError).code)")
            }
        }
    }

    /// Network suspension and ImageIO decoding execute away from the main actor.
    nonisolated private static func fetch(_ url: URL, session: URLSession) async throws -> CGImage {
        let (data, response) = try await session.data(from: url)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let finalURL = response.url, ArtworkRequestGate.allows(finalURL),
              let image = downsample(data) else { throw URLError(.cannotDecodeContentData) }
        return image
    }

    nonisolated static func downsample(_ data: Data, maxPixel: Int = 176) -> CGImage? {
        guard maxPixel > 0,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Reject a redirect before URLSession can send an insecure request.
private final class HTTPSArtworkRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(ArtworkRequestGate.allows) == true ? request : nil)
    }
}
