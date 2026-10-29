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
        // Thin adapters over macOS APIs (screens, hot keys, and later camera and focus).
        .target(
            name: "GlazerSystem",
            dependencies: ["GlazerCore"]
        ),
        .testTarget(
            name: "GlazerCoreTests",
            dependencies: ["GlazerCore"]
        ),
    ]
)
