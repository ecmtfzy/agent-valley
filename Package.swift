// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentValley",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "AgentValley"),
        .testTarget(name: "AgentValleyTests", dependencies: ["AgentValley"]),
    ]
)
