// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexPaceBar",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "CodexPaceBar", targets: ["CodexPaceBar"])
    ],
    targets: [
        .target(
            name: "CodexPaceBarCore",
            path: "Sources/CodexPaceBarCore"
        ),
        .target(
            name: "CodexPaceBarAppSupport",
            dependencies: ["CodexPaceBarCore"],
            path: "Sources/CodexPaceBarAppSupport"
        ),
        .executableTarget(
            name: "CodexPaceBar",
            dependencies: ["CodexPaceBarCore", "CodexPaceBarAppSupport"],
            path: "Sources/CodexPaceBar"
        ),
        .testTarget(
            name: "CodexPaceBarTests",
            dependencies: ["CodexPaceBarCore", "CodexPaceBarAppSupport"],
            path: "Tests/CodexPaceBarTests"
        )
    ]
)
