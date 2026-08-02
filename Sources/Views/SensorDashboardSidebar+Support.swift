//
//  SensorDashboardSidebar+Support.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import SwiftUI

// MARK: - Layout and timing constants

private enum SidebarSupportConstants {
  // Pending action timeouts
  static let setupActionTimeoutNanoseconds: UInt64 = 30_000_000_000
  static let openSystemSettingsTimeoutNanoseconds: UInt64 = 8_000_000_000
  static let boostFanControlTimeoutNanoseconds: UInt64 = 12_000_000_000

  // Minimum visible duration for setup spinner
  static let helperSetupMinimumVisibleDuration: TimeInterval = 0.75

  // Fan state delta thresholds for controller state label
  static let rampingDeltaThreshold: Double = 0.02

  // RPM ramping detection tolerances
  static let rampingNearMaxRPMOffset: Float = 50
  static let rampingMinimumToleranceRPM: Float = 250
  static let rampingToleranceFactor: Float = 0.05

  // Prominent action button label
  static let buttonLabelHStackSpacing: CGFloat = 8

  // Usage block layout (connected teal assist element)
  static let assistReadyTealOpacity: Double = 0.5
  static let connectorWidth: CGFloat = 2
  static let connectorFrameHeight: CGFloat = 6
  static let connectorVisualHeight: CGFloat = 6
  static let connectorCenterY: CGFloat = 3
  static let connectorEdgeInset: CGFloat = 14
  static let connectorHoldingOpacity: Double = 0.7
  static let connectorReadyOpacity: Double = 0.4
}

private let sensorDashboardSidebarLog = AppLog.make(category: "SensorDashboardSidebar")

extension SensorDashboardSidebar {
  enum SystemStatus { case green, orange, red }

  enum SidebarPendingAction: Hashable {
    case helperSetup
    case agentSetup
    case openSystemSettings
    case enableBoost
    case disableBoost
    case setFanControl(Bool)

    var logName: String {
      switch self {
      case .helperSetup: return "helper_setup"
      case .agentSetup: return "agent_setup"
      case .openSystemSettings: return "open_system_settings"
      case .enableBoost: return "enable_boost"
      case .disableBoost: return "disable_boost"
      case .setFanControl(let enabled):
        return enabled ? "enable_fan_control" : "disable_fan_control"
      }
    }

    var timeoutNanoseconds: UInt64 {
      switch self {
      case .helperSetup, .agentSetup:
        return SidebarSupportConstants.setupActionTimeoutNanoseconds
      case .openSystemSettings:
        return SidebarSupportConstants.openSystemSettingsTimeoutNanoseconds
      case .enableBoost, .disableBoost, .setFanControl:
        return SidebarSupportConstants.boostFanControlTimeoutNanoseconds
      }
    }

    var minimumVisibleDuration: TimeInterval {
      switch self {
      case .helperSetup:
        return SidebarSupportConstants.helperSetupMinimumVisibleDuration
      case .agentSetup, .openSystemSettings, .enableBoost, .disableBoost, .setFanControl:
        return 0
      }
    }
  }

  struct ActiveAssistState: Identifiable {
    let kind: LoadAssistKind
    let isHolding: Bool
    let floorPercent: Double
    let maxFloorFraction: Double

    var id: String { kind.rawValue }
  }

  struct SidebarProminentActionConfiguration {
    let title: String
    let systemImage: String?
    let tint: Color
    let active: Bool
    let isBusy: Bool
  }

  func usageBlock(
    label: String,
    icon: String,
    value: Double?,
    tint: Color,
    assist: ActiveAssistState?
  ) -> some View {
    let teal = Color(nsColor: .systemTeal)
    let barTint: Color
    if let assist {
      barTint =
        assist.isHolding
        ? teal
        : teal.opacity(SidebarSupportConstants.assistReadyTealOpacity)
    } else {
      barTint = tint
    }
    return VStack(spacing: 0) {
      usageRow(
        label: label,
        icon: icon,
        value: value,
        tint: barTint
      )
      if let assist {
        assistConnector(isHolding: assist.isHolding, floorFraction: assist.maxFloorFraction)
        loadAssistCaption(assist)
          .transition(
            .asymmetric(
              insertion: .opacity.combined(with: .move(edge: .top)),
              removal: .opacity
            )
          )
      }
    }
  }

  /// A short vertical teal tick that bridges the load bar to the badge with no gap,
  /// placed horizontally at the assist's max configured floor along the bar width.
  private func assistConnector(isHolding: Bool, floorFraction: Double) -> some View {
    let teal = Color(nsColor: .systemTeal)
    return GeometryReader { geometry in
      let inset = SidebarSupportConstants.connectorEdgeInset
      let rawX = geometry.size.width * CGFloat(floorFraction)
      let clampedX = min(max(rawX, inset), geometry.size.width - inset)
      Rectangle()
        .fill(
          teal.opacity(
            isHolding
              ? SidebarSupportConstants.connectorHoldingOpacity
              : SidebarSupportConstants.connectorReadyOpacity
          )
        )
        .frame(
          width: SidebarSupportConstants.connectorWidth,
          height: SidebarSupportConstants.connectorVisualHeight
        )
        .position(
          x: clampedX,
          y: SidebarSupportConstants.connectorCenterY
        )
    }
    .frame(height: SidebarSupportConstants.connectorFrameHeight)
  }

  var fanControlStateLabel: String {
    if presentation.chartState == .degraded {
      if installState.helperNeedsRepair { return "Helper Needs Repair" }
      if presentation.installationStep == .helperMissing { return "System Helper Required" }
      if presentation.installationStep == .agentMissing {
        return "Background Control Required"
      }
      if presentation.installationStep == .helperAwaitingApproval {
        return "Approval Required"
      }
      if presentation.installationStep == .agentAwaitingApproval {
        return "Approval Required"
      }
      return presentation.telemetryFresh ? "Telemetry Unavailable" : "Agent Not Responding"
    }
    if presentation.controlState == .monitorOnly { return "Monitor only" }
    if !fanControlReady { return "Not Set Up" }
    if boost { return "Boost active" }
    return curveModel.isActive ? "Curve active" : "Off"
  }

  var fanControlStateColor: Color {
    if presentation.chartState == .degraded { return statusColor }
    if !fanControlReady { return .secondary }
    if boost { return Color(nsColor: .systemOrange) }
    return curveModel.isActive ? Color.accentColor : .secondary
  }

  var controllerStateLabel: String {
    let targetPercent = clampedPercent(runtime.commandedTargetPercent)
    let target = Int((targetPercent * 100).rounded())

    guard let observedPercent else {
      return "Targeting \(target)%"
    }

    let delta = targetPercent - observedPercent
    if delta > SidebarSupportConstants.rampingDeltaThreshold {
      return "Stepping up toward \(target)%"
    }
    if delta < -SidebarSupportConstants.rampingDeltaThreshold {
      return "Cooling down toward \(target)%"
    }
    return "Targeting \(target)%"
  }

  var observedPercent: Double? {
    let percents = runtime.fans.compactMap { fan -> Double? in
      guard let range = effectiveRPMRange(for: fan), fan.actualRPM > 0 else { return nil }
      return clampedPercent(Double((fan.actualRPM - range.min) / (range.max - range.min)))
    }
    guard !percents.isEmpty else { return nil }
    return percents.reduce(0, +) / Double(percents.count)
  }

  func effectiveRPMRange(for fan: AgentFanSnapshot) -> (min: Float, max: Float)? {
    let minRPM: Float = underdriveEnabled ? 0 : fan.minRPM
    let maxRPM: Float = overdriveEnabled ? max(fan.maxRPM, overdriveTargetRPM) : fan.maxRPM
    guard maxRPM > minRPM else { return nil }
    return (minRPM, maxRPM)
  }

  func clampedPercent(_ percent: Double) -> Double {
    max(0, min(1, percent))
  }

  func isRamping(_ fan: AgentFanSnapshot) -> Bool {
    let target = fan.targetRPM
    guard target > 0 else { return false }
    if fan.actualRPM >= fan.maxRPM - SidebarSupportConstants.rampingNearMaxRPMOffset {
      return false
    }
    let tolerance = max(
      SidebarSupportConstants.rampingMinimumToleranceRPM,
      target * SidebarSupportConstants.rampingToleranceFactor)
    return abs(fan.actualRPM - target) > tolerance
  }

  var boostButton: some View {
    let targetAction: SidebarPendingAction = boost ? .disableBoost : .enableBoost
    let configuration = SidebarProminentActionConfiguration(
      title: boostButtonLabel,
      systemImage: "bolt.fill",
      tint: Color(nsColor: .systemOrange),
      active: boost,
      isBusy: isPendingAction(targetAction)
    )
    return sidebarProminentActionButton(configuration) {
      sensorDashboardSidebarLog.notice(
        "sidebar.boost.toggled next_enabled=\((!boost), privacy: .public)"
      )
      beginPendingAction(targetAction)
      let enabled = !boost
      Task {
        do {
          try await runtime.setBoostEnabled(enabled)
          await MainActor.run {
            boost = enabled
          }
        } catch {
          sensorDashboardSidebarLog.notice(
            "sidebar.boost.command_failed enabled=\(enabled, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=keep-current-state"
          )
          await MainActor.run {
            completePendingAction(targetAction, reason: "command-failed")
          }
        }
      }
    }
    .help(boostHelp)
    .accessibilityValue(boost ? "1" : "0")
    .accessibilityIdentifier(AppAccessibilityIdentifier.Dashboard.boost)
  }

  private var boostButtonLabel: String {
    if isPendingAction(.enableBoost) { return "Boosting Fans" }
    if isPendingAction(.disableBoost) { return "Stopping Boost" }
    return boost ? "Stop Boost" : "Boost Fans"
  }

  func sidebarProminentActionButton(
    _ configuration: SidebarProminentActionConfiguration,
    action: @escaping () -> Void
  ) -> some View {
    Button {
      guard !configuration.isBusy else { return }
      action()
    } label: {
      sidebarProminentActionButtonLabel(configuration)
    }
    .buttonStyle(
      SidebarProminentButtonStyle(
        tint: configuration.tint,
        isActive: configuration.active,
        isBusy: configuration.isBusy
      )
    )
    .frame(maxWidth: .infinity)
    .allowsHitTesting(!configuration.isBusy)
  }

  /// Only the label's own content. Padding, font, color, and the glass
  /// background belong to `SidebarProminentButtonStyle`.
  @ViewBuilder
  private func sidebarProminentActionButtonLabel(
    _ configuration: SidebarProminentActionConfiguration
  ) -> some View {
    HStack(spacing: SidebarSupportConstants.buttonLabelHStackSpacing) {
      Spacer(minLength: 0)

      if configuration.isBusy {
        ProgressView()
          .controlSize(.small)
          .tint(configuration.active ? Color.white : configuration.tint)
      } else if let systemImage = configuration.systemImage {
        Image(systemName: systemImage)
          .foregroundStyle(
            configuration.active ? Color.white : configuration.tint
          )
      }

      Text(configuration.title)
        .lineLimit(1)

      Spacer(minLength: 0)
    }
  }

  var boostHelp: String {
    "Pins all fans to 100% (or Overdrive target) while enabled."
  }
}
