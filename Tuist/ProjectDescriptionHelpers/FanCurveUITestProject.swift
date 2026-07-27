//
//  FanCurveUITestProject.swift
//  ProjectDescriptionHelpers
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import ProjectDescription

public func makeFanCurveUITestTarget(
  deploymentTargets: DeploymentTargets,
  sourceExclusions: [Path]
) -> Target {
  .target(
    name: "FanCurveUITests",
    destinations: [.mac],
    product: .uiTests,
    bundleId: "$(APP_BUNDLE_ID).ui-tests",
    deploymentTargets: deploymentTargets,
    infoPlist: .default,
    sources: [
      "Tests/FanCurveUITests/**",
      "Sources/Common/AppAccessibilityIdentifier.swift",
      .generated("Generated/FanCurve/Config.generated.swift"),
      .glob(
        "Sources/TestControl/**",
        excluding: sourceExclusions
      ),
    ],
    dependencies: [
      .external(name: "AppLog")
    ],
    settings: .settings(
      base: [
        "TEST_HOST": "",
        "TEST_TARGET_NAME": "",
      ]
    )
  )
}

public func makeFanCurveUITestScheme() -> Scheme {
  .scheme(
    name: "FanCurveUITests",
    shared: true,
    buildAction: .buildAction(targets: [.target("FanCurveUITests")]),
    testAction: .targets(
      [.testableTarget(target: "FanCurveUITests")],
      arguments: .arguments(
        environmentVariables: [
          "FANCURVE_TEST_CONTROL_PATH": "$(FANCURVE_TEST_CONTROL_PATH)"
        ]
      ),
      configuration: "Debug",
      attachDebugger: false,
      expandVariableFromTarget: .target("FanCurveUITests")
    )
  )
}

public func makeFanCurveServiceSmokeTarget(
  deploymentTargets: DeploymentTargets
) -> Target {
  .target(
    name: "FanCurveServiceSmokeTests",
    destinations: [.mac],
    product: .uiTests,
    bundleId: "$(APP_BUNDLE_ID).service-smoke-tests",
    deploymentTargets: deploymentTargets,
    infoPlist: .default,
    sources: [
      "Tests/FanCurveServiceSmokeTests/**",
      "Sources/Common/AppAccessibilityIdentifier.swift",
      .generated("Generated/FanCurve/Config.generated.swift"),
    ],
    dependencies: [
      .external(name: "Nimble")
    ],
    settings: .settings(
      base: [
        "TEST_HOST": "",
        "TEST_TARGET_NAME": "",
      ]
    )
  )
}

public func makeFanCurveServiceSmokeScheme() -> Scheme {
  .scheme(
    name: "FanCurveServiceSmokeTests",
    shared: true,
    buildAction: .buildAction(targets: [.target("FanCurveServiceSmokeTests")]),
    testAction: .targets(
      [.testableTarget(target: "FanCurveServiceSmokeTests")],
      configuration: "Release",
      attachDebugger: false,
      expandVariableFromTarget: .target("FanCurveServiceSmokeTests")
    )
  )
}

public func makeTestControlContractScheme() -> Scheme {
  .scheme(
    name: "TestControlContractTests",
    shared: true,
    buildAction: .buildAction(targets: [.target("TestControlContractTests")]),
    testAction: .targets(
      [.testableTarget(target: "TestControlContractTests")],
      configuration: "Debug"
    )
  )
}
