//
//  SensorDashboardSidebar+Status.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-05-10.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

// MARK: - Layout and threshold constants

private enum SidebarStatusConstants {
  // Assist caption row
  static let assistCaptionHStackSpacing: CGFloat = 6
  static let assistCaptionIconSize: CGFloat = 11
  static let assistCaptionHorizontalPadding: CGFloat = 10
  static let assistCaptionVerticalPadding: CGFloat = 5
  static let assistCaptionLineLimit = 1
  static let assistCaptionMinimumScaleFactor: Double = 0.85

  // Percent scale factor (fractional to whole number)
  static let percentScale: Double = 100

  // Usage row layout
  static let usageRowVStackSpacing: CGFloat = 4
  static let usageRowBarCornerRadius: CGFloat = 2
  static let usageRowBarTrackOpacity: Double = 0.15
  static let usageRowBarHeight: CGFloat = 4
  static let usageRowAnimationDuration: Double = 0.32

  // Fan row layout
  static let fanRowInnerVStackSpacing: CGFloat = 2
  static let fanRowTopHStackSpacing: CGFloat = 4
  static let fanRowRPMHStackSpacing: CGFloat = 3
  static let fanRowRPMAnimationDuration: Double = 0.38
  static let fanRowRampingSpinnerScale: CGFloat = 0.7

  // Temperature color thresholds in degrees Celsius
  static let tempGreenMaxCelsius: Double = 55
  static let tempYellowMaxCelsius: Double = 75
  static let tempOrangeMaxCelsius: Double = 90
}

extension SensorDashboardSidebar {
  var systemStatus: SystemStatus {
    let helperReachable =
      runtime.isFresh ? runtime.helperReachable : installState.helperReachable
    let setupNeedsAttention =
      installState.step == .helperAwaitingApproval
      || installState.step == .agentAwaitingApproval
      || installState.step == .agentMissing
    if setupNeedsAttention {
      return .orange
    }
    if installState.step == .helperMissing {
      // A reachable helper with a stale registration record is a non-blocking
      // repair rather than an outage, so it must not read as hard red while live
      // telemetry is flowing. Only an unreachable helper is a true red failure.
      return helperReachable ? .orange : .red
    }
    if runtime.runtimeState.health == .ownershipPreempted {
      return .orange
    }
    if presentation.chartState == .degraded {
      return .red
    }
    let isFullyOperational =
      helperReachable
      && installState.agentEnabled
      && installState.agentLive
      && installState.agentSnapshotCompatible
    if isFullyOperational {
      return .green
    }
    if helperReachable, installState.agentEnabled, !installState.agentLive {
      return .orange
    }
    if installState.agentEnabled, !helperReachable {
      return .orange
    }
    return .red
  }

  var statusColor: Color {
    switch systemStatus {
    case .green: return Color(nsColor: .systemGreen)
    case .orange: return Color(nsColor: .systemOrange)
    case .red: return Color(nsColor: .systemRed)
    }
  }

  var assistStates: [ActiveAssistState] {
    guard fanControlReady, presentation.showsRuntimeStats, curveModel.isActive, !boost else {
      return []
    }
    let floorPercent = runtime.assistFloorPercent ?? 0
    var states: [ActiveAssistState] = []
    for kind in LoadAssistKind.allCases {
      let enabled = kind == .cpu ? cpuLoadAssistEnabled : gpuLoadAssistEnabled
      guard enabled else { continue }
      states.append(
        ActiveAssistState(
          kind: kind,
          isHolding: isDisplayedHolding(kind),
          floorPercent: floorPercent
        ))
    }
    return states
  }

  func loadAssistCaption(_ assist: ActiveAssistState) -> some View {
    let color = Color(nsColor: .systemTeal)
    let floor = Int((assist.floorPercent * SidebarStatusConstants.percentScale).rounded())
    let text = "\(assist.kind.title) Enabled"
    let usageWord = assist.kind == .gpu ? "graphics" : "CPU"
    let help =
      assist.isHolding
      ? "\(assist.kind.title) is keeping the fan at \(floor)% while \(usageWord) usage is high."
      : "\(assist.kind.title) raises the fan when \(usageWord) usage climbs."

    return HStack(
      alignment: .center, spacing: SidebarStatusConstants.assistCaptionHStackSpacing
    ) {
      ZStack {
        Image(systemName: "arrow.up.forward.circle")
          .opacity(assist.isHolding ? 0 : 1)
        Image(systemName: "arrow.up.forward.circle.fill")
          .opacity(assist.isHolding ? 1 : 0)
      }
      .font(.system(size: SidebarStatusConstants.assistCaptionIconSize))
      Text(text)
        .font(.caption)
        .lineLimit(SidebarStatusConstants.assistCaptionLineLimit)
        .minimumScaleFactor(SidebarStatusConstants.assistCaptionMinimumScaleFactor)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .foregroundStyle(color)
    .padding(.horizontal, SidebarStatusConstants.assistCaptionHorizontalPadding)
    .padding(.vertical, SidebarStatusConstants.assistCaptionVerticalPadding)
    .modifier(LoadFloorGlassModifier(color: color, active: assist.isHolding))
    .help(help)
  }

  func runtimeLoadValue(_ value: Double) -> Double? {
    guard presentation.showsRuntimeStats else { return nil }
    return value
  }

  private var usageRowAnimation: Animation? {
    guard renderMode.allowsLiveAnimation else { return nil }
    return .easeOut(duration: SidebarStatusConstants.usageRowAnimationDuration)
  }

  func usageRow(label: String, icon: String, value: Double?, tint: Color) -> some View {
    let roundedValue = value.map { rawValue in Int(rawValue.rounded()) }
    return VStack(alignment: .leading, spacing: SidebarStatusConstants.usageRowVStackSpacing) {
      HStack(alignment: .firstTextBaseline) {
        Image(systemName: icon)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(label)
          .font(.callout)
          .foregroundColor(.secondary)
        Spacer()
        if let roundedValue {
          Text("\(roundedValue)%")
            .font(.system(.callout, design: .rounded).weight(.medium))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(usageRowAnimation, value: roundedValue)
        } else {
          Text("--")
            .font(.system(.callout, design: .rounded).weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: SidebarStatusConstants.usageRowBarCornerRadius)
            .fill(
              Color.secondary.opacity(SidebarStatusConstants.usageRowBarTrackOpacity))
          if let value {
            RoundedRectangle(
              cornerRadius: SidebarStatusConstants.usageRowBarCornerRadius
            )
            .fill(tint)
            .frame(
              width: geometry.size.width
                * CGFloat(value / SidebarStatusConstants.percentScale)
            )
            .animation(usageRowAnimation, value: value)
          }
        }
      }
      .frame(height: SidebarStatusConstants.usageRowBarHeight)
    }
  }

  func fanRow(_ fan: AgentFanSnapshot) -> some View {
    let displayedRPM = Int(fan.actualRPM)
    return HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: SidebarStatusConstants.fanRowInnerVStackSpacing) {
        HStack(spacing: SidebarStatusConstants.fanRowTopHStackSpacing) {
          fanIcon(fan: fan)
          Text("Fan \(fan.id)")
            .font(.callout)
            .foregroundColor(.secondary)
          if fan.manualMode {
            Text("Manual")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
        HStack(
          alignment: .firstTextBaseline,
          spacing: SidebarStatusConstants.fanRowRPMHStackSpacing
        ) {
          Text("\(displayedRPM)")
            .font(.system(.title3, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(
              renderMode.allowsLiveAnimation
                ? .easeOut(
                  duration: SidebarStatusConstants.fanRowRPMAnimationDuration)
                : nil,
              value: displayedRPM
            )
          Text("RPM")
            .font(.caption)
            .foregroundColor(.secondary)
          if renderMode.allowsLiveAnimation, isRamping(fan) {
            ProgressView()
              .controlSize(.mini)
              .scaleEffect(SidebarStatusConstants.fanRowRampingSpinnerScale)
              .help(
                "Ramping to \(Int(fan.targetRPM)) RPM. Spinner stops when the fan settles within range."
              )
          }
        }
      }
      Spacer()
    }
  }

  func fanIcon(fan: AgentFanSnapshot) -> some View {
    RPMFanIcon(
      rpm: fan.actualRPM,
      minRPM: fan.minRPM,
      maxRPM: fan.maxRPM,
      renderMode: renderMode
    )
  }

  var tempColor: Color {
    guard let temperature = liveTemperatureCelsius else { return .secondary }
    if temperature < SidebarStatusConstants.tempGreenMaxCelsius {
      return Color(nsColor: .systemGreen)
    }
    if temperature < SidebarStatusConstants.tempYellowMaxCelsius {
      return Color(nsColor: .systemYellow)
    }
    if temperature < SidebarStatusConstants.tempOrangeMaxCelsius {
      return Color(nsColor: .systemOrange)
    }
    return Color(nsColor: .systemRed)
  }

  var displayedTemperature: Int? {
    guard let temperature = liveTemperatureCelsius else { return nil }
    return Int(unit.convert(fromCelsius: temperature).rounded())
  }

  var liveTemperatureCelsius: Double? {
    guard presentation.showsRuntimeStats else { return nil }
    let temperature = runtime.governingTemperature
    guard temperature > 0 else { return nil }
    return temperature
  }
}
