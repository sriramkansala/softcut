// swift-tools-version:6.0
import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Softcut",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Softcut", targets: ["Softcut"]),
        .executable(name: "softcut-cli", targets: ["SoftcutCLI"]),
        .library(name: "SoftcutCore", targets: ["SoftcutCore"]),
        .library(name: "SoftcutUI", targets: ["SoftcutUI"]),
    ],
    targets: [
        .target(name: "SoftcutCore", swiftSettings: swift5),
        .target(name: "SoftcutUI", dependencies: ["SoftcutCore"], swiftSettings: swift5),
        .executableTarget(name: "Softcut", dependencies: ["SoftcutCore", "SoftcutUI"], swiftSettings: swift5),
        .executableTarget(name: "SoftcutCLI", dependencies: ["SoftcutCore", "SoftcutUI"], path: "Sources/softcut-cli", swiftSettings: swift5),
        .testTarget(name: "SoftcutCoreTests", dependencies: ["SoftcutCore"], resources: [.copy("Fixtures")], swiftSettings: swift5),
        .testTarget(name: "SoftcutUITests", dependencies: ["SoftcutUI", "SoftcutCore"], swiftSettings: swift5),
    ]
)
