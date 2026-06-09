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
        .executableTarget(
            name: "CodexPaceBar",
            dependencies: ["CodexPaceBarCore"],
            path: "Sources/CodexPaceBar"
        ),
        .testTarget(
            name: "CodexPaceBarTests",
            dependencies: ["CodexPaceBarCore"],
            path: "Tests/CodexPaceBarTests"
        )
    ]
)
