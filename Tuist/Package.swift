// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanCurveDependencies",
    dependencies: [
        .package(url: "https://github.com/agoodkind/macos-smc-fan.git", branch: "main"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1"),
    ]
)
