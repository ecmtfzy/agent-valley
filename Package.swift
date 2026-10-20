// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentValley",
    platforms: [.macOS("15.0")],
    dependencies: [
        // Updates for the signed releases. Exact, so a build never meets a version nobody tried.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(name: "AgentValley", dependencies: [.product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "AgentValleyTests", dependencies: ["AgentValley"]),
    ]
)
