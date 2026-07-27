import ProjectDescription
import ProjectDescriptionHelpers

let appName = "FanCurve"
let appDisplayName = "Fan Curve"
let helperDisplayName = "Fan Curve Hardware Helper"
let projectName = "FanCurveApp"
let agentExecutableName = "FanCurveAgent"
let agentDisplayName = "Fan Curve Background Control"
let organizationName = "goodkind.io"
let macOSDeploymentTarget = DeploymentTargets.macOS("13.0")

let debug = Configuration.debug(
  name: "Debug",
  xcconfig: "Config/debug.xcconfig"
)

let release = Configuration.release(
  name: "Release",
  xcconfig: "Config/release.xcconfig"
)

let generatedConfigScript = TargetScript.pre(
  path: "Scripts/GenerateConfig.swift",
  name: "Generate Config from xcconfig",
  outputPaths: [
    "$(SRCROOT)/Generated/$(TARGET_NAME)/Config.generated.swift",
    "$(SRCROOT)/Generated/$(TARGET_NAME)/App-Info.plist",
    "$(SRCROOT)/Generated/$(TARGET_NAME)/Agent-Info.plist",
    "$(SRCROOT)/Generated/$(TARGET_NAME)/agent-launchd.plist",
    "$(SRCROOT)/Generated/$(TARGET_NAME)/io.goodkind.smcfanhelper.plist",
    "$(SRCROOT)/Generated/$(TARGET_NAME)/helper-info.plist",
    "$(SRCROOT)/Generated/$(TARGET_NAME)/helper-launchd.plist",
  ]
)

let sparkleCurrentPath =
  "$(BUILT_PRODUCTS_DIR)/$(PRODUCT_NAME).app/Contents/Frameworks/Sparkle.framework/Versions/Current"
let sparkleXPCPath = "\(sparkleCurrentPath)/XPCServices"

// Keep bundle assembly declarative in Tuist and reserve scripting for Sparkle's
// documented inside-out signing requirements.
let signSparkleScript = TargetScript.post(
  path: "Scripts/SignSparkle.swift",
  name: "Sign Sparkle nested code",
  inputPaths: [
    "\(sparkleCurrentPath)/Updater.app",
    "\(sparkleXPCPath)/Downloader.xpc",
    "\(sparkleXPCPath)/Installer.xpc",
    "\(sparkleCurrentPath)/Autoupdate",
    "$(BUILT_PRODUCTS_DIR)/$(PRODUCT_NAME).app/Contents/Frameworks/Sparkle.framework",
  ]
)

let projectSettings = Settings.settings(
  base: [
    "SWIFT_VERSION": "6.0",
    "MACOSX_DEPLOYMENT_TARGET": "13.0",
    "ARCHS": "arm64",
    "APP_DISPLAY_NAME": .string(appDisplayName),
    "HELPER_DISPLAY_NAME": .string(helperDisplayName),
    "AGENT_DISPLAY_NAME": .string(agentDisplayName),
    "AGENT_EXECUTABLE_NAME": .string(agentExecutableName),
    "SPARKLE_FEED_URL": "",
    "SPARKLE_PUBLIC_ED_KEY": "",
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
  ],
  configurations: [debug, release],
  defaultSettings: .recommended
)

let signingSettings: SettingsDictionary = [
  "CODE_SIGN_STYLE": "Manual",
  "CODE_SIGN_IDENTITY": "$(CODE_SIGN_IDENTITY)",
  "DEVELOPMENT_TEAM": "$(DEVELOPMENT_TEAM)",
]

let externalDependencies: [TargetDependency] = [
  .external(name: "SMCFanKit"),
  .external(name: "AppLog"),
  .external(name: "SMCFanXPCClient"),
  .external(name: "SMCFanProtocol"),
]

let testControlAdapterSourceExclusions: [Path] = [
  "Sources/TestControl/CLI/**",
  "Sources/TestControl/Controlled*.swift",
  "Sources/TestControl/*Adapters.swift",
]

let modelTestSources: SourceFilesList = [
  .generated("Generated/FanCurve/Config.generated.swift"),
  .glob(
    "Sources/TestControl/**",
    excluding: testControlAdapterSourceExclusions
  ),
  "Sources/App/L10n.swift",
  "Sources/Common/SharedConfigKeys.swift",
  "Sources/Common/AppAccessibilityIdentifier.swift",
  "Sources/Common/AgentFanSnapshot.swift",
  "Sources/Common/AgentControllerMode.swift",
  "Sources/Common/AgentSnapshot.swift",
  "Sources/Common/AppVisibilityState.swift",
  "Sources/Common/FanCurveAgentXPCProtocol.swift",
  "Sources/Common/ManagedService.swift",
  "Sources/Common/RuntimeState.swift",
  "Sources/Common/SetupActionAffordance+Codable.swift",
  "Sources/Models/TemperatureUnit.swift",
  "Sources/Models/TemperatureAxisScale.swift",
  "Sources/Models/SensorState.swift",
  "Sources/Models/CurveColumns.swift",
  "Sources/Models/CurveAxisScale.swift",
  "Sources/Models/CurvePoint.swift",
  "Sources/Models/AgentServiceMutationResult.swift",
  "Sources/Models/FixedColumnCurve.swift",
  "Sources/Models/FanCommand.swift",
  "Sources/Models/FanCommandMapping.swift",
  "Sources/Models/InterpolationMode.swift",
  "Sources/Models/HelperServiceRegistration.swift",
  "Sources/Models/LoadAssistKind.swift",
  "Sources/Models/LoadAssistCurveColumns.swift",
  "Sources/Models/ThermalDemandSource.swift",
  "Sources/Models/LoadAssistStore.swift",
  "Sources/Models/WorkloadGenerator.swift",
  "Sources/Models/CPULoadSampler.swift",
  "Sources/Models/IOAcceleratorPerformanceStatistics.swift",
  "Sources/Models/AcousticRampGovernor.swift",
  "Sources/Models/FanResponse.swift",
  "Sources/Models/CurvePresets.swift",
  "Sources/Models/EventArtifactWriter.swift",
  "Sources/Models/CurveInterpolation.swift",
  "Sources/Models/LiveMarkerPresentation.swift",
  "Sources/Services/AppRenderActivity.swift",
  "Sources/Common/DevOverrides.swift",
  "Sources/Views/SettingsTab.swift",
  "Sources/Views/SettingsMonitoringGate.swift",
]

let strictConcurrencySettings: SettingsDictionary = [
  "OTHER_SWIFT_FLAGS": "$(inherited) -enable-upcoming-feature StrictConcurrency"
]

let project = Project(
  name: projectName,
  organizationName: organizationName,
  settings: projectSettings,
  targets: [
    .target(
      name: appName,
      destinations: [.mac],
      product: .app,
      bundleId: "$(APP_BUNDLE_ID)",
      deploymentTargets: macOSDeploymentTarget,
      infoPlist: .file(path: "Generated/FanCurve/App-Info.plist"),
      sources: [
        "Sources/App/**",
        "Sources/Models/**",
        "Sources/Views/**",
        "Sources/Services/**",
        "Sources/Common/**",
        "Sources/TestControl/TestControl*.swift",
        .generated("Generated/FanCurve/Config.generated.swift"),
      ],
      resources: [
        "Sources/App/Base.lproj/**",
        "Sources/App/Assets.xcassets",
      ],
      copyFiles: [
        .executables(
          name: "Embed Agent",
          files: [
            .buildProduct(name: agentExecutableName, codeSignOnCopy: true)
          ]
        ),
        .wrapper(
          name: "Embed Launch Agent Plist",
          subpath: "Contents/Library/LaunchAgents",
          files: [
            .glob(pattern: "Generated/FanCurve/agent-launchd.plist")
          ]
        ),
        .executables(
          name: "Embed Helper Daemon",
          files: [
            .buildProduct(name: "SMCFanHelper", codeSignOnCopy: true)
          ]
        ),
        .wrapper(
          name: "Embed Helper Daemon Plist",
          subpath: "Contents/Library/LaunchDaemons",
          files: [
            .glob(pattern: "Generated/FanCurve/io.goodkind.smcfanhelper.plist")
          ]
        ),
      ],
      scripts: [
        generatedConfigScript,
        signSparkleScript,
      ],
      dependencies: externalDependencies + [
        .external(name: "Sparkle"),
        .target(name: "FanCurveAgent"),
        .target(name: "SMCFanHelper"),
      ],
      settings: .settings(
        base: signingSettings.merging([
          "PRODUCT_NAME": .string(appDisplayName),
          "EXECUTABLE_NAME": .string(appName),
          "PRODUCT_BUNDLE_IDENTIFIER": .string("$(APP_BUNDLE_ID)"),
          "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
          "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "",
        ]) { _, new in new }
      )
    ),
    .target(
      name: "FanCurveAgent",
      destinations: [.mac],
      product: .commandLineTool,
      bundleId: "$(AGENT_BUNDLE_ID)",
      deploymentTargets: macOSDeploymentTarget,
      infoPlist: .file(path: "Generated/FanCurveAgent/Agent-Info.plist"),
      sources: [
        "Sources/Agent/**",
        "Sources/App/L10n.swift",
        "Sources/Models/**",
        "Sources/Services/Agent*.swift",
        "Sources/Services/FanCurveAgentClient*.swift",
        "Sources/Common/**",
        .glob(
          "Sources/TestControl/**",
          excluding: ["Sources/TestControl/CLI/**"]
        ),
        .generated("Generated/FanCurveAgent/Config.generated.swift"),
      ],
      scripts: [
        generatedConfigScript
      ],
      dependencies: externalDependencies,
      settings: .settings(
        base: signingSettings.merging([
          "PRODUCT_BUNDLE_IDENTIFIER": .string("$(AGENT_BUNDLE_ID)"),
          "CREATE_INFOPLIST_SECTION_IN_BINARY": "YES",
          "SKIP_INSTALL": "YES",
        ]) { _, new in new }
      )
    ),
    .target(
      name: "FanCurveTestControl",
      destinations: [.mac],
      product: .commandLineTool,
      bundleId: "$(APP_BUNDLE_ID).test-control",
      deploymentTargets: macOSDeploymentTarget,
      infoPlist: .default,
      sources: [
        .glob(
          "Sources/TestControl/**",
          excluding: Array(testControlAdapterSourceExclusions.dropFirst())
        )
      ],
      dependencies: [
        .external(name: "AppLog")
      ],
      settings: .settings(
        base: signingSettings.merging([
          "PRODUCT_BUNDLE_IDENTIFIER": .string("$(APP_BUNDLE_ID).test-control"),
          "CODE_SIGNING_ALLOWED": "YES",
          "CODE_SIGNING_REQUIRED": "YES",
          "CREATE_INFOPLIST_SECTION_IN_BINARY": "YES",
          "ENABLE_HARDENED_RUNTIME": "YES",
          "SKIP_INSTALL": "YES",
        ]) { _, new in new }
      )
    ),
    .target(
      name: "SMCFanHelper",
      destinations: [.mac],
      product: .commandLineTool,
      bundleId: "$(HELPER_BUNDLE_ID)",
      deploymentTargets: macOSDeploymentTarget,
      infoPlist: .default,
      sources: [
        "Sources/SMCFanHelper/**"
      ],
      scripts: [
        generatedConfigScript
      ],
      dependencies: [
        .external(name: "SMCFanHelperCore"),
        .external(name: "SMCFanKit"),
        .external(name: "AppLog"),
        .external(name: "SMCFanProtocol"),
      ],
      settings: .settings(
        base: signingSettings.merging([
          "PRODUCT_NAME": "io.goodkind.smcfanhelper",
          "PRODUCT_BUNDLE_IDENTIFIER": .string("$(HELPER_BUNDLE_ID)"),
          "ENABLE_HARDENED_RUNTIME": "YES",
          "SKIP_INSTALL": "YES",
          "CREATE_INFOPLIST_SECTION_IN_BINARY": "NO",
          "OTHER_LDFLAGS": [
            "-sectcreate", "__TEXT", "__info_plist",
            "$(SRCROOT)/Generated/$(TARGET_NAME)/helper-info.plist",
            "-sectcreate", "__TEXT", "__launchd_plist",
            "$(SRCROOT)/Generated/$(TARGET_NAME)/helper-launchd.plist",
          ],
        ]) { _, new in new }
      )
    ),
    .target(
      name: "FanCurveModels",
      destinations: [.mac],
      product: .framework,
      bundleId: "$(APP_BUNDLE_ID).models",
      deploymentTargets: macOSDeploymentTarget,
      infoPlist: .default,
      sources: modelTestSources,
      dependencies: [
        .external(name: "AppLog")
      ],
      settings: .settings(base: strictConcurrencySettings)
    ),
    .target(
      name: "ModelTests",
      destinations: [.mac],
      product: .unitTests,
      bundleId: "$(APP_BUNDLE_ID).model-tests",
      deploymentTargets: macOSDeploymentTarget,
      infoPlist: .default,
      sources: [
        .glob(
          "Tests/ModelTests/**",
          excluding: ["Tests/ModelTests/TestControl*Tests.swift"]
        )
      ],
      dependencies: [
        .target(name: "FanCurveModels"),
        .external(name: "Nimble"),
      ]
    ),
    .target(
      name: "TestControlContractTests",
      destinations: [.mac],
      product: .unitTests,
      bundleId: "$(APP_BUNDLE_ID).test-control-tests",
      deploymentTargets: macOSDeploymentTarget,
      infoPlist: .default,
      sources: [
        "Tests/ModelTests/TestControl*Tests.swift"
      ],
      dependencies: [
        .target(name: "FanCurveModels"),
        .external(name: "Nimble"),
      ]
    ),
    makeFanCurveUITestTarget(
      deploymentTargets: macOSDeploymentTarget,
      sourceExclusions: testControlAdapterSourceExclusions
    ),
    makeFanCurveServiceSmokeTarget(
      deploymentTargets: macOSDeploymentTarget
    ),
    .target(
      name: "FanCurveAgentTests",
      destinations: [.mac],
      product: .unitTests,
      bundleId: "$(APP_BUNDLE_ID).agent-tests",
      deploymentTargets: macOSDeploymentTarget,
      infoPlist: .default,
      sources: [
        .glob(
          "Sources/Agent/**",
          excluding: ["Sources/Agent/FanCurveAgentMain.swift"]
        ),
        "Sources/App/L10n.swift",
        "Sources/Models/**",
        "Sources/Services/Agent*.swift",
        "Sources/Services/FanCurveAgentClient*.swift",
        "Sources/Common/**",
        .glob(
          "Sources/TestControl/**",
          excluding: ["Sources/TestControl/CLI/**"]
        ),
        "Tests/AgentTests/**",
        .generated("Generated/FanCurveAgent/Config.generated.swift"),
      ],
      dependencies: externalDependencies + [
        .external(name: "Nimble")
      ]
    ),
  ],
  schemes: [
    .scheme(
      name: "FanCurveCoverage",
      shared: true,
      buildAction: .buildAction(
        targets: [
          .target(appName),
          .target("FanCurveTestControl"),
          .target("FanCurveUITests"),
        ]
      ),
      testAction: .targets(
        [
          .testableTarget(target: "ModelTests"),
          .testableTarget(target: "TestControlContractTests"),
          .testableTarget(target: "FanCurveAgentTests"),
        ],
        configuration: "Debug"
      )
    ),
    .scheme(
      name: appName,
      shared: true,
      buildAction: .buildAction(targets: [.target(appName)]),
      testAction: .targets(
        [
          .testableTarget(target: "ModelTests"),
          .testableTarget(target: "TestControlContractTests"),
          .testableTarget(target: "FanCurveAgentTests"),
        ],
        configuration: "Debug"
      ),
      runAction: .runAction(configuration: "Debug"),
      archiveAction: .archiveAction(configuration: "Release"),
      profileAction: .profileAction(configuration: "Release"),
      analyzeAction: .analyzeAction(configuration: "Debug")
    ),
    .scheme(
      name: "FanCurveAgent",
      shared: true,
      buildAction: .buildAction(targets: [.target("FanCurveAgent")]),
      runAction: .runAction(configuration: "Debug"),
      archiveAction: .archiveAction(configuration: "Release"),
      profileAction: .profileAction(configuration: "Release"),
      analyzeAction: .analyzeAction(configuration: "Debug")
    ),
    .scheme(
      name: "FanCurveAgentTests",
      shared: true,
      buildAction: .buildAction(targets: [.target("FanCurveAgentTests")]),
      testAction: .targets(
        [.testableTarget(target: "FanCurveAgentTests")],
        configuration: "Debug"
      )
    ),
    makeFanCurveUITestScheme(),
    makeFanCurveServiceSmokeScheme(),
    .scheme(
      name: "FanCurveTestControl",
      shared: true,
      buildAction: .buildAction(targets: [.target("FanCurveTestControl")]),
      runAction: .runAction(configuration: "Debug"),
      analyzeAction: .analyzeAction(configuration: "Debug")
    ),
    makeTestControlContractScheme(),
    .scheme(
      name: "SMCFanHelper",
      shared: true,
      buildAction: .buildAction(targets: [.target("SMCFanHelper")]),
      runAction: .runAction(configuration: "Debug"),
      archiveAction: .archiveAction(configuration: "Release"),
      profileAction: .profileAction(configuration: "Release"),
      analyzeAction: .analyzeAction(configuration: "Debug")
    ),
  ]
)
