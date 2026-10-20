// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMenuBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexMenuBar", targets: ["CodexMenuBar"])],
    targets: [
        .target(name: "CodexQuotaCore"),
        .executableTarget(name: "CodexMenuBar", dependencies: ["CodexQuotaCore"]),
        .testTarget(name: "CodexQuotaCoreTests", dependencies: ["CodexQuotaCore"])
    ]
)
