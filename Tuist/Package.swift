// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "FanCurveDependencies",
  dependencies: [
    .package(
      url: "https://github.com/agoodkind/macos-smc-fan.git",
      exact: "0.4.4"
    ),
    .package(
      url: "https://github.com/Quick/Nimble.git",
      revision: "727f75d91a0f7501d08d938966d17e6728b76a2a"
    ),
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1"),
  ]
)
