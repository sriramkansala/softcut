// swift-tools-version:6.0
import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Glide",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Glide", targets: ["Glide"]),
        .executable(name: "glide-cli", targets: ["GlideCLI"]),
        .library(name: "GlideCore", targets: ["GlideCore"]),
        .library(name: "GlideUI", targets: ["GlideUI"]),
    ],
    targets: [
        .target(name: "GlideCore", swiftSettings: swift5),
        .target(name: "GlideUI", dependencies: ["GlideCore"], swiftSettings: swift5),
        .executableTarget(name: "Glide", dependencies: ["GlideCore", "GlideUI"], swiftSettings: swift5),
        .executableTarget(name: "GlideCLI", dependencies: ["GlideCore", "GlideUI"], path: "Sources/glide-cli", swiftSettings: swift5),
        .testTarget(name: "GlideCoreTests", dependencies: ["GlideCore"], resources: [.copy("Fixtures")], swiftSettings: swift5),
        .testTarget(name: "GlideUITests", dependencies: ["GlideUI", "GlideCore"], swiftSettings: swift5),
    ]
)
