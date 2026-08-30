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

  // RPM ramping detection tolerances
  static let rampingNearMaxRPMOffset: Float = 50
  static let rampingMinimumToleranceRPM: Float = 250
  static let rampingToleranceFactor: Float = 0.05

  // Prominent action button label
  static let buttonLabelHStackSpacing: CGFloat = 8

  // Usage block layout
  static let assistReadyTealOpacity: Double = 0.5
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

  var fanControlStateLabel: String {
    if presentation.chartState == .degraded {
      let helperNeedsSetup =
        presentation.installationStep == .helperMissing
        || presentation.installationStep == .helperAwaitingApproval
      if helperNeedsSetup {
        return SystemHelperPresentation.resolve(
          state: installState.systemHelperState,
          repairInFlight: installState.isRegisteringHelper
        ).status
      }
      if presentation.installationStep == .agentMissing {
        return "Background Control Required"
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

  /// Boost as a standard switch row under the Fan Control toggle. The switch
  /// is orange while Boost is on and the system's normal gray while off.
  var boostButton: some View {
    HStack {
      Text("Boost")
        .font(.body)
      Spacer()
      HStack(spacing: SidebarSupportConstants.buttonLabelHStackSpacing) {
        if boostToggleBusy {
          ProgressView()
            .controlSize(.mini)
        }
        Toggle("", isOn: boostBinding)
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.regular)
          .tint(Color(nsColor: .systemOrange))
          .disabled(hasPendingAction() && !boostToggleBusy)
          .help(boostHelp)
          .accessibilityValue(boost ? "1" : "0")
          .accessibilityIdentifier(AppAccessibilityIdentifier.Dashboard.boost)
      }
    }
  }

  var boostToggleBusy: Bool {
    isPendingAction(.enableBoost) || isPendingAction(.disableBoost)
  }

  private var boostBinding: Binding<Bool> {
    Binding(
      get: { boost },
      set: { enabled in
        guard !hasPendingAction() else { return }
        sensorDashboardSidebarLog.notice(
          "sidebar.boost.toggled next_enabled=\(enabled, privacy: .public)"
        )
        beginPendingAction(enabled ? .enableBoost : .disableBoost)
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
              completePendingAction(
                enabled ? .enableBoost : .disableBoost, reason: "command-failed")
            }
          }
        }
      }
    )
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
    .sidebarProminentButtonStyle(
      tint: configuration.tint,
      isActive: configuration.active,
      isBusy: configuration.isBusy
    )
    .frame(maxWidth: .infinity)
    .allowsHitTesting(!configuration.isBusy)
  }

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
    .font(.callout.weight(.medium))
    .frame(maxWidth: .infinity)
  }

  var boostHelp: String {
    "Pins all fans to 100% (or Overdrive target) while enabled."
  }
}
