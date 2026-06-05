import ProjectDescription

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
        "$(SRCROOT)/Derived/Generated/$(TARGET_NAME)/Config.generated.swift",
        "$(SRCROOT)/Derived/Generated/$(TARGET_NAME)/App-Info.plist",
        "$(SRCROOT)/Derived/Generated/$(TARGET_NAME)/Agent-Info.plist",
        "$(SRCROOT)/Derived/Generated/$(TARGET_NAME)/agent-launchd.plist",
        "$(SRCROOT)/Derived/Generated/$(TARGET_NAME)/helper-daemon.plist",
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

let embedHelperDaemonScript = TargetScript.post(
    path: "Scripts/EmbedHelperDaemon.swift",
    name: "Embed Helper Daemon",
    inputPaths: [
        "$(SMC_FAN_HELPER_APP)/Contents/MacOS/$(HELPER_BUNDLE_ID)",
        "$(SRCROOT)/Derived/Generated/FanCurve/helper-daemon.plist",
    ],
    outputPaths: [
        "$(BUILT_PRODUCTS_DIR)/$(PRODUCT_NAME).app/Contents/MacOS/$(HELPER_BUNDLE_ID)",
        "$(BUILT_PRODUCTS_DIR)/$(PRODUCT_NAME).app/Contents/Library/LaunchDaemons/$(HELPER_BUNDLE_ID).plist",
    ]
)

let projectSettings = Settings.settings(
    base: [
        "SWIFT_VERSION": "6.0",
        "MACOSX_DEPLOYMENT_TARGET": "13.0",
        "MARKETING_VERSION": "0.1.0",
        "CURRENT_PROJECT_VERSION": "1",
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

let modelTestSources: SourceFilesList = [
    "Sources/App/L10n.swift",
    "Sources/Common/SharedConfigKeys.swift",
    "Sources/Common/AgentFanSnapshot.swift",
    "Sources/Common/AgentControllerMode.swift",
    "Sources/Common/AgentSnapshot.swift",
    "Sources/Common/AppVisibilityState.swift",
    "Sources/Common/RuntimeState.swift",
    "Sources/Common/SetupActionAffordance+Codable.swift",
    "Sources/Models/TemperatureUnit.swift",
    "Sources/Models/TemperatureAxisScale.swift",
    "Sources/Models/SensorState.swift",
    "Sources/Models/CurveColumns.swift",
    "Sources/Models/CurveAxisScale.swift",
    "Sources/Models/CurvePoint.swift",
    "Sources/Models/FixedColumnCurve.swift",
    "Sources/Models/FanCommand.swift",
    "Sources/Models/FanCommandMapping.swift",
    "Sources/Models/InterpolationMode.swift",
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
            infoPlist: .file(path: "Derived/Generated/FanCurve/App-Info.plist"),
            sources: [
                "Sources/App/**",
                "Sources/Models/**",
                "Sources/Views/**",
                "Sources/Services/**",
                "Sources/Common/**",
                .generated("Derived/Generated/FanCurve/Config.generated.swift"),
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
                        .glob(pattern: "Derived/Generated/FanCurve/agent-launchd.plist")
                    ]
                ),
            ],
            scripts: [
                generatedConfigScript,
                embedHelperDaemonScript,
                signSparkleScript,
            ],
            dependencies: externalDependencies + [
                .external(name: "Sparkle"),
                .target(name: "FanCurveAgent"),
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
            infoPlist: .file(path: "Derived/Generated/FanCurveAgent/Agent-Info.plist"),
            sources: [
                "Sources/Agent/**",
                "Sources/App/L10n.swift",
                "Sources/Models/**",
                "Sources/Services/FanCurveAgentClient.swift",
                "Sources/Services/DevToggleOverride.swift",
                "Sources/Common/**",
                .generated("Derived/Generated/FanCurveAgent/Config.generated.swift"),
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
                "Tests/ModelTests/**"
            ],
            dependencies: [
                .target(name: "FanCurveModels"),
                .external(name: "Nimble"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: appName,
            shared: true,
            buildAction: .buildAction(targets: [.target(appName)]),
            testAction: .targets([.testableTarget(target: "ModelTests")], configuration: "Debug"),
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
    ]
)
