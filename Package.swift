// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Glazer",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Glazer", targets: ["GlazerApp"]),
        .executable(name: "glazer-camera-check", targets: ["GlazerCameraCheck"]),
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
        // The menu bar app: lifecycle, state and SwiftUI views.
        .executableTarget(
            name: "GlazerApp",
            dependencies: ["GlazerCore", "GlazerSystem"]
        ),
        // A command-line check of the camera and Vision: `swift run glazer-camera-check`.
        .executableTarget(
            name: "GlazerCameraCheck",
            dependencies: ["GlazerCore", "GlazerSystem"]
        ),
        .testTarget(
            name: "GlazerCoreTests",
            dependencies: ["GlazerCore"]
        ),
        .testTarget(
            name: "GlazerSystemTests",
            dependencies: ["GlazerSystem", "GlazerCore"]
        ),
    ]
)
