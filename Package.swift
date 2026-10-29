// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Glazer",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Pure logic. No AppKit, no camera, no UI. Everything here is unit-tested.
        .target(
            name: "GlazerCore"
        ),
        .testTarget(
            name: "GlazerCoreTests",
            dependencies: ["GlazerCore"]
        ),
    ]
)
