import Foundation
import CryptoKit

public struct ReleaseVersion: Comparable, Equatable, Sendable {
    public let components: [Int]
    public init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        components = parts.map { Int($0)! }
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

public struct AppRelease: Decodable, Sendable {
    public struct Asset: Decodable, Sendable {
        public let name: String
        public let browser_download_url: URL
        public let size: Int
    }
    public let tag_name: String
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]
    public var version: ReleaseVersion? { ReleaseVersion(tag_name) }
    public var displayVersion: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    public var page: URL { URL(string: "https://github.com/beefysalad/Shima/releases/tag/\(tag_name)")! }
    public func asset(named name: String) -> Asset? {
        guard version != nil, !draft, !prerelease else { return nil }
        return assets.first {
            $0.name == name && $0.size > 0 && $0.size <= 30_000_000 &&
            $0.browser_download_url.absoluteString == "https://github.com/beefysalad/Shima/releases/download/\(tag_name)/\(name)"
        }
    }
}

public enum UpdateValidation {
    public static func checksum(_ data: Data, name: String, manifest: String) -> Bool {
        let matches = manifest.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard parts.count == 2, parts[1] == name || parts[1] == "*" + name else { return nil }
            return String(parts[0]).lowercased()
        }
        guard matches.count == 1 else { return false }
        return matches[0] == SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public static func archivePathsAreSafe(_ listing: String) -> Bool {
        let paths = listing.split(separator: "\n")
        return !paths.isEmpty && paths.allSatisfy { path in
            !path.hasPrefix("/") && !path.contains("\\") &&
            !path.split(separator: "/").contains("..") &&
            (path == "Shima.app/" || path.hasPrefix("Shima.app/") || path.hasPrefix("__MACOSX/"))
        }
    }
}

/// Same-volume renames keep the old bundle available until the new app launches.
public enum UpdateSwap {
    public static func install(staged: URL, target: URL, backup: URL,
                               move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) throws {
        try move(target, backup)
        do { try move(staged, target) }
        catch {
            do { try move(backup, target) }
            catch { throw NSError(domain: "ShimaUpdate", code: 2, userInfo: [NSLocalizedDescriptionKey: "Update and rollback failed. Your previous app is at \(backup.path)."] ) }
            throw error
        }
    }
}
