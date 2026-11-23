import Foundation
import Testing
@testable import Shima
@testable import ShimaCore

private final class UpdateHTTPProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        #expect(request.timeoutInterval == 60)
        if url.lastPathComponent == "network-error" {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        if url.lastPathComponent == "never-request" {
            Issue.record("Advertised oversized files must be rejected before starting a download")
        }
        let body = Data((url.lastPathComponent == "incomplete" ? "ab" :
                        url.lastPathComponent == "oversized" ? "abcd" : "abc").utf8)
        let response: URLResponse
        if url.lastPathComponent == "non-http" {
            response = URLResponse(url: url, mimeType: nil, expectedContentLength: body.count, textEncodingName: nil)
        } else {
            response = HTTPURLResponse(url: url, statusCode: url.lastPathComponent == "http-error" ? 503 : 200,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct AppUpdaterFetchTests {
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateHTTPProtocol.self]
        return URLSession(configuration: configuration)
    }
    private func asset(_ path: String, size: Int = 3) -> AppRelease.Asset {
        AppRelease.Asset(name: "fixture", browser_download_url: URL(string: "https://updates.example.test/\(path)")!, size: size)
    }
    private func failureMessage(_ path: String, size: Int = 3, limit: Int = 3) async -> String {
        let session = session()
        defer { session.invalidateAndCancel() }
        do {
            _ = try await AppUpdater.fetch(asset(path, size: size), limit: limit, session: session)
            Issue.record("Invalid download was accepted: \(path)")
            return ""
        } catch { return error.localizedDescription }
    }

    @Test func acceptsCompleteDownloadAtTheExactSizeLimit() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let data = try await AppUpdater.fetch(asset("complete"), limit: 3, session: session)
        #expect(data == Data("abc".utf8))
    }
    @Test func rejectsAdvertisedOversizeBeforeMakingARequest() async {
        #expect(await failureMessage("never-request", size: 4) == "The release file is too large.")
    }
    @Test func rejectsStreamThatExceedsTheLimitDespiteAdvertisedSize() async {
        #expect(await failureMessage("oversized") == "The release file is too large.")
    }
    @Test func rejectsIncompleteAndUnexpectedlyLongDownloads() async {
        #expect(await failureMessage("incomplete") == "The download is incomplete.")
        #expect(await failureMessage("complete", size: 2) == "The download is incomplete.")
    }
    @Test func rejectsHTTPFailureAndNonHTTPResponse() async {
        for path in ["http-error", "non-http"] {
            #expect(await failureMessage(path) == "Couldn’t download the update. Try again later.")
        }
    }
    @Test func propagatesTransportFailure() async {
        #expect(await failureMessage("network-error") == URLError(.networkConnectionLost).localizedDescription)
    }
}
