import ProjectDescription

private let xcodeUpgradeCheckMajor = 26
private let xcodeUpgradeCheckMinor = 4
private let xcodeUpgradeCheckPatch = 1

let workspace = Workspace(
  name: "FanCurveApp",
  projects: [
    "."
  ],
  generationOptions: .options(
    lastXcodeUpgradeCheck: Version(
      xcodeUpgradeCheckMajor,
      xcodeUpgradeCheckMinor,
      xcodeUpgradeCheckPatch
    )
  )
)
