// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIPulse",
    platforms: [.macOS(.v14)],
    products: [
        // The app is "AIPulseApp" rather than "AIPulse": product/target names
        // that differ only by case ("AIPulse" vs CLI "aipulse") collide in
        // build directories and binary paths on case-insensitive APFS.
        .executable(name: "AIPulseApp", targets: ["AIPulseApp"]),
        .executable(name: "aipulse", targets: ["aipulse"]),
        .library(name: "AIPulseKit", targets: ["AIPulseKit"]),
    ],
    targets: [
        .target(name: "AIPulseKit"),
        .executableTarget(
            name: "AIPulseApp",
            dependencies: ["AIPulseKit"],
            path: "Sources/AIPulse"
        ),
        .executableTarget(
            name: "aipulse",
            dependencies: ["AIPulseKit"],
            path: "Sources/AIPulseCLI"
        ),
        .testTarget(
            name: "AIPulseKitTests",
            dependencies: ["AIPulseKit"]
        ),
    ]
)
