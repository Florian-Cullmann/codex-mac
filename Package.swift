// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexUsage",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexUsage", targets: ["CodexUsage"])],
    targets: [
        .target(name: "CodexUsageCore"),
        .executableTarget(name: "CodexUsage", dependencies: ["CodexUsageCore"]),
        .testTarget(name: "CodexUsageCoreTests", dependencies: ["CodexUsageCore"])
    ]
)
