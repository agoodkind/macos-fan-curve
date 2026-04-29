import ProjectDescription

let workspace = Workspace(
    name: "FanCurveApp",
    projects: [
        ".",
    ],
    generationOptions: .options(
        lastXcodeUpgradeCheck: Version(26, 4, 1)
    )
)
