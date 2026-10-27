// swift-tools-version: 6.0
import PackageDescription

#if TUIST
  import ProjectDescription

  // Remove each target override after its package declares a minimum macOS
  // version of 12.0 or later.
  let minimumDeploymentTargetSettings: Settings = .settings(
    base: ["MACOSX_DEPLOYMENT_TARGET": "12.0"]
  )

  let packageSettings = PackageSettings(
    targetSettings: [
      "AppLog": minimumDeploymentTargetSettings,
      "CwlCatchException": minimumDeploymentTargetSettings,
      "CwlCatchExceptionSupport": minimumDeploymentTargetSettings,
      "CwlMachBadInstructionHandler": minimumDeploymentTargetSettings,
      "CwlPreconditionTesting": minimumDeploymentTargetSettings,
      "Logging": minimumDeploymentTargetSettings,
      "Nimble": minimumDeploymentTargetSettings,
      "NimbleObjectiveC": minimumDeploymentTargetSettings,
      "SMCFanHelperCore": minimumDeploymentTargetSettings,
      "SMCFanKit": minimumDeploymentTargetSettings,
      "SMCFanProtocol": minimumDeploymentTargetSettings,
      "SMCFanXPCClient": minimumDeploymentTargetSettings,
      "SMCKit": minimumDeploymentTargetSettings,
    ]
  )
#endif

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
