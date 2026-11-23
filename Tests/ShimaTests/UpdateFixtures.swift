import Foundation
import Testing
@testable import ShimaCore

func updateRelease(tag: String = "v1.1.0", draft: Bool = false, prerelease: Bool = false,
                   assets: [String] = ["Shima-1.1.0.zip", "SHA256SUMS"]) throws -> AppRelease {
    let payload: [String: Any] = [
        "tag_name": tag, "draft": draft, "prerelease": prerelease,
        "assets": assets.map { name in
            ["name": name, "size": 1,
             "browser_download_url": "https://github.com/beefysalad/Shima/releases/download/\(tag)/\(name)"] as [String: Any]
        },
    ]
    return try JSONDecoder().decode(AppRelease.self, from: JSONSerialization.data(withJSONObject: payload))
}
