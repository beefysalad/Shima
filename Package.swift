// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "shima",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ShimaCore", targets: ["ShimaCore"]),
        .executable(name: "Shima", targets: ["Shima"]),
        .executable(name: "shimactl", targets: ["shimactl"]),
        .executable(name: "ShimaUpdater", targets: ["ShimaUpdater"]),
    ],
    targets: [
        // State, event bus and the Unix-socket server (logic only; testable).
        .target(name: "ShimaCore"),
        // The menu-bar-less accessory app: SwiftUI hosted in a non-activating NSPanel.
        .executableTarget(name: "Shima", dependencies: ["ShimaCore"], exclude: ["Resources"]),
        // CLI that Claude Code hooks call. Must always exit 0 quickly.
        .executableTarget(name: "shimactl"),
        .executableTarget(name: "ShimaUpdater", dependencies: ["ShimaCore"]),
        .testTarget(name: "ShimaCoreTests", dependencies: ["ShimaCore"]),
        .testTarget(name: "ShimaTests", dependencies: ["Shima"]),
    ]
)
