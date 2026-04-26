import ProjectDescription

let appName = "FanCurve"
let projectName = "FanCurveApp"
let agentExecutableName = "FanCurveAgent"
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
    script: """
    "${SRCROOT}/Scripts/generate-config.sh"
    """,
    name: "Generate Config from xcconfig",
    outputPaths: [
        "$(DERIVED_FILE_DIR)/Generated/Config.generated.swift",
        "$(DERIVED_FILE_DIR)/Generated/agent-launchd.plist",
    ]
)

let bundleAgentScript = TargetScript.post(
    script: """
    set -euo pipefail
    AGENT_SRC="${BUILT_PRODUCTS_DIR}/${AGENT_EXECUTABLE_NAME}"
    APP_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app"
    AGENTS_DIR="${APP_DIR}/Contents/Library/LaunchAgents"
    MACOS_DIR="${APP_DIR}/Contents/MacOS"
    mkdir -p "${AGENTS_DIR}"
    cp "${AGENT_SRC}" "${MACOS_DIR}/"
    cp "${DERIVED_FILE_DIR}/Generated/agent-launchd.plist" \
       "${AGENTS_DIR}/${AGENT_BUNDLE_ID}.plist"
    """,
    name: "Bundle agent into app",
    outputPaths: [
        "$(BUILT_PRODUCTS_DIR)/$(PRODUCT_NAME).app/Contents/MacOS/$(AGENT_EXECUTABLE_NAME)",
        "$(BUILT_PRODUCTS_DIR)/$(PRODUCT_NAME).app/Contents/Library/LaunchAgents/$(AGENT_BUNDLE_ID).plist",
    ]
)

let projectSettings = Settings.settings(
    base: [
        "SWIFT_VERSION": "6.0",
        "MACOSX_DEPLOYMENT_TARGET": "13.0",
        "MARKETING_VERSION": "0.1.0",
        "CURRENT_PROJECT_VERSION": "1",
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

let appInfoPlist: [String: Plist.Value] = [
    "CFBundleName": .string("Fan Curve"),
    "CFBundleDisplayName": .string("Fan Curve"),
    "LSApplicationCategoryType": .string("public.app-category.utilities"),
    "LSMinimumSystemVersion": .string("13.0"),
    "NSMainStoryboardFile": .string(""),
    "NSPrincipalClass": .string("NSApplication"),
    "SUEnableAutomaticChecks": .boolean(true),
    "SUAllowsAutomaticUpdates": .boolean(true),
    "SUScheduledCheckInterval": .integer(86400),
    "SUAutomaticallyUpdate": .boolean(false),
    "SUFeedURL": .string("$(SPARKLE_FEED_URL)"),
    "SUPublicEDKey": .string("$(SPARKLE_PUBLIC_ED_KEY)"),
]

let externalDependencies: [TargetDependency] = [
    .external(name: "SMCFanKit"),
    .external(name: "AppLog"),
    .external(name: "SMCFanXPCClient"),
    .external(name: "SMCFanProtocol"),
]

let modelTestSources: SourceFilesList = [
    "Sources/Models/TemperatureUnit.swift",
    "Sources/Models/SystemUsage.swift",
    "Sources/Models/SensorState.swift",
    "Sources/Models/LoadAssist.swift",
    "Sources/Models/CurveTypes.swift",
    "Sources/Models/WorkloadGenerator.swift",
    "Sources/Models/CPULoadSampler.swift",
    "Sources/Models/CurvePresets.swift",
    "Sources/Models/EventArtifactWriter.swift",
    "Sources/Models/CurveInterpolation.swift",
]

let strictConcurrencySettings: SettingsDictionary = [
    "OTHER_SWIFT_FLAGS": "$(inherited) -enable-upcoming-feature StrictConcurrency",
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
            infoPlist: .extendingDefault(with: appInfoPlist),
            sources: [
                "Sources/App/**",
                "Sources/Models/**",
                "Sources/Views/**",
                "Sources/Services/**",
                "Sources/Common/**",
                .generated("$(DERIVED_FILE_DIR)/Generated/Config.generated.swift"),
            ],
            resources: [
                "Sources/App/Base.lproj/**",
                "Sources/App/Assets.xcassets",
            ],
            scripts: [
                generatedConfigScript,
                bundleAgentScript,
            ],
            dependencies: externalDependencies + [
                .external(name: "Sparkle"),
                .target(name: "FanCurveAgent"),
            ],
            settings: .settings(
                base: signingSettings.merging([
                    "PRODUCT_NAME": .string(appName),
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
            infoPlist: .default,
            sources: [
                "Sources/Agent/**",
                "Sources/Models/**",
                "Sources/Services/XPCClient.swift",
                "Sources/Common/**",
                .generated("$(DERIVED_FILE_DIR)/Generated/Config.generated.swift"),
            ],
            scripts: [
                generatedConfigScript,
            ],
            dependencies: externalDependencies,
            settings: .settings(
                base: signingSettings.merging([
                    "PRODUCT_BUNDLE_IDENTIFIER": .string("$(AGENT_BUNDLE_ID)"),
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
                .external(name: "AppLog"),
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
                "Tests/ModelTests/**",
            ],
            dependencies: [
                .target(name: "FanCurveModels"),
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
