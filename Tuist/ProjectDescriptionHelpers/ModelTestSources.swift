//
//  ModelTestSources.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-28.
//  Copyright © 2026, all rights reserved.
//

import ProjectDescription

/// Sources compiled into the `FanCurveModels` test target.
///
/// The list names individual files rather than globbing `Sources/Models/**`
/// because the model target deliberately excludes app and agent types that
/// would drag UI or XPC dependencies into a unit-test binary. It lives here
/// rather than in `Project.swift` so the manifest stays a manifest.
public func makeModelTestSources(
  testControlAdapterSourceExclusions: [Path]
) -> SourceFilesList {
  [
    .generated("Generated/FanCurve/Config.generated.swift"),
    .glob(
      "Sources/TestControl/**",
      excluding: testControlAdapterSourceExclusions
    ),
    "Sources/App/L10n.swift",
    "Sources/Common/SharedConfigKeys.swift",
    "Sources/Common/AppAccessibilityIdentifier.swift",
    "Sources/Common/BuildFingerprint.swift",
    "Sources/Common/AgentFanSnapshot.swift",
    "Sources/Common/AgentControllerMode.swift",
    "Sources/Common/AgentSnapshot.swift",
    "Sources/Common/AppVisibilityState.swift",
    "Sources/Common/FanCurveAgentXPCProtocol.swift",
    "Sources/Common/ManagedServiceStatus.swift",
    "Sources/Common/RuntimeState.swift",
    "Sources/Common/SetupActionAffordance+Codable.swift",
    "Sources/Common/SystemHelperRuntimeState.swift",
    "Sources/Models/TemperatureUnit.swift",
    "Sources/Models/TemperatureAxisScale.swift",
    "Sources/Models/SensorState.swift",
    "Sources/Models/SensorKeyResolver.swift",
    "Sources/Models/CurveColumns.swift",
    "Sources/Models/CurveAxisScale.swift",
    "Sources/Models/CurvePoint.swift",
    "Sources/Models/AgentServiceMutationResult.swift",
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
    "Sources/Models/AgentPresence.swift",
    "Sources/Models/TickCoordinator.swift",
    "Sources/Models/TickHeartbeatScheduler.swift",
    "Sources/Models/DeadlineBoundedOperation.swift",
    "Sources/Models/AgentShutdownSequencer.swift",
    "Sources/Models/ExpandedRangeConfigurationStore.swift",
    "Sources/Models/FanResponse.swift",
    "Sources/Models/CurvePresets.swift",
    "Sources/Models/EventArtifactWriter.swift",
    "Sources/Models/CurveInterpolation.swift",
    "Sources/Models/LiveMarkerPresentation.swift",
    "Sources/Models/SystemHelperClassifier.swift",
    "Sources/Models/SystemHelperFanResetSequencer.swift",
    "Sources/Models/SystemHelperPresentation.swift",
    "Sources/Services/AppRenderActivity.swift",
    "Sources/Common/DevOverrides.swift",
    "Sources/Views/SettingsTab.swift",
    "Sources/Views/SettingsMonitoringGate.swift",
  ]
}
