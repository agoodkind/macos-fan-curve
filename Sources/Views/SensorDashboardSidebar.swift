//
//  SensorDashboardSidebar.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import SwiftUI

private let sensorDashboardSidebarViewLog = AppLog.make(category: "SensorDashboardSidebar")

// MARK: - Layout Constants

private enum SensorDashboardSidebarConstants {
  // Outer layout
  static let outerVStackSpacing: CGFloat = 24
  static let horizontalPadding: CGFloat = 20
  static let topPadding: CGFloat = 24
  static let bottomPadding: CGFloat = 20
  static let dividerOpacity: Double = 0.15

  // Hero section
  static let heroVStackSpacing: CGFloat = 4
  static let heroHStackSpacing: CGFloat = 6
  static let tempIndicatorDotSize: CGFloat = 6
  static let tempValueHStackSpacing: CGFloat = 2
  static let tempAnimationDuration: Double = 0.38
  static let unavailableHStackSpacing: CGFloat = 6

  // Usage and fans sections
  static let usageVStackSpacing: CGFloat = 10
  static let gpuTintOpacity: Double = 0.55
  static let fansVStackSpacing: CGFloat = 10
  static let fanRowHorizontalPadding: CGFloat = 10
  static let fanRowVerticalPadding: CGFloat = 8
  static let fanRowCornerRadius: CGFloat = 8
  static let fanRowBackgroundOpacity: Double = 0.06
  static let fanRowStrokeOpacity: Double = 0.08
  static let fanRowStrokeLineWidth: CGFloat = 0.5

  // Controls section
  static let controlsVStackSpacing: CGFloat = 12
  static let controlsLabelVStackSpacing: CGFloat = 2
  static let controlsHStackSpacing: CGFloat = 6

  // Timing
  static let nanosecondsPerSecond: Double = 1_000_000_000

  // Load assist holding-state smoothing
  static let holdingReleaseDelaySeconds: Double = 0.6
  static let holdingCrossfadeDuration: Double = 0.3
}

struct SensorDashboardSidebar: View {
  @State private var pendingAction: SidebarPendingAction?
  @State private var pendingActionStartDate: Date?
  @State private var displayedHolding: Set<LoadAssistKind> = []
  @State private var holdingReleaseToken: [LoadAssistKind: Int] = [:]
  @ObservedObject var runtime: FanCurveAgentClient
  @ObservedObject var curveModel: FanCurveModel
  @ObservedObject var installState: InstallationState
  let renderMode: AppRenderMode
  let unit: TemperatureUnit
  @Binding var boost: Bool
  let cpuLoadAssistEnabled: Bool
  let gpuLoadAssistEnabled: Bool
  let presentation: DashboardPresentationState

  var fanControlReady: Bool {
    presentation.controlState == .fanControl
  }

  var body: some View {
    VStack(alignment: .leading, spacing: SensorDashboardSidebarConstants.outerVStackSpacing) {
      heroSection
      usageSection
      fansSection
      Divider().opacity(SensorDashboardSidebarConstants.dividerOpacity)
      controlsSection
    }
    .padding(.horizontal, SensorDashboardSidebarConstants.horizontalPadding)
    .padding(.top, SensorDashboardSidebarConstants.topPadding)
    .padding(.bottom, SensorDashboardSidebarConstants.bottomPadding)
    .onChange(of: installState.step) { _ in
      reconcilePendingAction(reason: "installation-step-changed")
    }
    .onChange(of: installState.lastError) { _ in
      reconcilePendingAction(reason: "installation-error-changed")
    }
    .onChange(of: runtime.snapshot) { _ in
      reconcilePendingAction(reason: "runtime-snapshot-changed")
    }
    .onChange(of: runtime.activeAssistKinds) { _ in
      syncDisplayedHolding(animated: true)
    }
    .onAppear {
      syncDisplayedHolding(animated: false)
    }
    .task(id: pendingAction) {
      guard let pendingAction else { return }
      let clock = ContinuousClock()
      do {
        try await clock.sleep(
          until: clock.now.advanced(
            by: .nanoseconds(Int64(pendingAction.timeoutNanoseconds))
          )
        )
        guard !Task.isCancelled else { return }
        await MainActor.run {
          completePendingAction(
            pendingAction,
            reason: "timeout"
          )
        }
      } catch {
        sensorDashboardSidebarViewLog.notice(
          "sidebar.pending.timer.cancelled action=\(pendingAction.logName, privacy: .public) recovery=keep-current-pending-state"
        )
      }
    }
    .accessibilityIdentifier(AppAccessibilityIdentifier.Dashboard.temperature)
    .task(id: pendingActionStartDate) {
      guard let pendingAction else { return }
      let remainingNanoseconds = pendingActionMinimumRemainingNanoseconds()
      guard remainingNanoseconds > 0 else { return }
      let clock = ContinuousClock()
      do {
        try await clock.sleep(
          until: clock.now.advanced(
            by: .nanoseconds(Int64(remainingNanoseconds))
          )
        )
        guard !Task.isCancelled else { return }
        await MainActor.run {
          reconcilePendingAction(reason: "minimum-duration-elapsed")
        }
      } catch {
        sensorDashboardSidebarViewLog.notice(
          "sidebar.pending.minimum_timer.cancelled action=\(pendingAction.logName, privacy: .public) recovery=keep-current-pending-state"
        )
      }
    }
  }

  private var heroSection: some View {
    VStack(alignment: .leading, spacing: SensorDashboardSidebarConstants.heroVStackSpacing) {
      HStack(spacing: SensorDashboardSidebarConstants.heroHStackSpacing) {
        Image(systemName: "thermometer.medium")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Text("CPU Temperature")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Circle()
          .fill(tempColor)
          .frame(
            width: SensorDashboardSidebarConstants.tempIndicatorDotSize,
            height: SensorDashboardSidebarConstants.tempIndicatorDotSize
          )
      }

      if let displayedTemperature {
        HStack(
          alignment: .firstTextBaseline,
          spacing: SensorDashboardSidebarConstants.tempValueHStackSpacing
        ) {
          Text("\(displayedTemperature)")
            .font(.system(.largeTitle, design: .rounded).weight(.regular))
            .foregroundStyle(.primary)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(
              .easeOut(
                duration: SensorDashboardSidebarConstants.tempAnimationDuration),
              value: displayedTemperature)
          Text(unit.symbol)
            .font(.title3)
            .foregroundStyle(.secondary)
        }
      } else {
        HStack(
          alignment: .center,
          spacing: SensorDashboardSidebarConstants.unavailableHStackSpacing
        ) {
          Text("--")
            .font(.system(.largeTitle, design: .rounded).weight(.regular))
            .foregroundStyle(.secondary)
            .monospacedDigit()
          Text("unavailable")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var usageSection: some View {
    let assistStates = self.assistStates
    return VStack(spacing: SensorDashboardSidebarConstants.usageVStackSpacing) {
      usageBlock(
        label: "CPU",
        icon: "cpu",
        value: runtimeLoadValue(runtime.cpuLoadPercent),
        tint: Color.accentColor,
        assist: assistStates.first { $0.kind == .cpu }
      )
      .accessibilityIdentifier(AppAccessibilityIdentifier.Dashboard.cpuLoad)
      usageBlock(
        label: "GPU",
        icon: "memorychip",
        value: runtimeLoadValue(runtime.gpuLoadPercent),
        tint: Color.accentColor.opacity(SensorDashboardSidebarConstants.gpuTintOpacity),
        assist: assistStates.first { $0.kind == .gpu }
      )
      .accessibilityIdentifier(AppAccessibilityIdentifier.Dashboard.gpuLoad)
    }
  }

  private var fansSection: some View {
    VStack(spacing: SensorDashboardSidebarConstants.fansVStackSpacing) {
      if presentation.showsRuntimeStats {
        ForEach(runtime.fans) { fan in
          fanRow(fan)
            .padding(
              .horizontal, SensorDashboardSidebarConstants.fanRowHorizontalPadding
            )
            .padding(.vertical, SensorDashboardSidebarConstants.fanRowVerticalPadding)
            .background(
              RoundedRectangle(
                cornerRadius: SensorDashboardSidebarConstants.fanRowCornerRadius
              )
              .fill(
                Color.secondary.opacity(
                  SensorDashboardSidebarConstants.fanRowBackgroundOpacity))
            )
            .overlay(
              RoundedRectangle(
                cornerRadius: SensorDashboardSidebarConstants.fanRowCornerRadius
              )
              .stroke(
                Color.primary.opacity(
                  SensorDashboardSidebarConstants.fanRowStrokeOpacity),
                lineWidth: SensorDashboardSidebarConstants.fanRowStrokeLineWidth)
            )
            .accessibilityIdentifier(
              AppAccessibilityIdentifier.Dashboard.fanRow(fan.id)
            )
        }
      }
    }
  }

  private var showsFanControlStateSubtitle: Bool {
    presentation.controlState != .setup
      && presentation.chartState != .degraded
  }

  private var controlsSection: some View {
    VStack(spacing: SensorDashboardSidebarConstants.controlsVStackSpacing) {
      HStack {
        VStack(
          alignment: .leading,
          spacing: SensorDashboardSidebarConstants.controlsLabelVStackSpacing
        ) {
          Text("Fan Control")
            .font(.body)
          if showsFanControlStateSubtitle {
            Text(fanControlStateLabel)
              .font(.caption)
              .foregroundColor(fanControlStateColor)
          }
        }
        Spacer()
        if presentation.showsFanControlToggle {
          HStack(spacing: SensorDashboardSidebarConstants.controlsHStackSpacing) {
            if fanControlToggleBusy {
              ProgressView()
                .controlSize(.mini)
            }
            Toggle("", isOn: fanControlBinding)
              .labelsHidden()
              .toggleStyle(.switch)
              .controlSize(.regular)
              .tint(Color.accentColor)
              .disabled(boost || pendingAction != nil)
              .help(fanControlToggleHelp)
              .accessibilityValue(curveModel.isActive ? "1" : "0")
              .accessibilityIdentifier(AppAccessibilityIdentifier.Dashboard.fanControl)
          }
        }
      }

      if presentation.controlState == .setup || presentation.helperActionVisible {
        setupButton
      } else if presentation.showsBoostControl, curveModel.isActive {
        boostButton
          .transition(
            .asymmetric(
              insertion: .opacity.combined(with: .move(edge: .top)),
              removal: .opacity
            )
          )
      }
    }
  }
}

extension SensorDashboardSidebar {
  func isPendingAction(_ action: SidebarPendingAction) -> Bool {
    pendingAction == action
  }

  func hasPendingAction() -> Bool {
    pendingAction != nil
  }

  /// Maps the agent's raw `activeAssistKinds` into the debounced `displayedHolding`
  /// set that drives the teal element. Turning on is immediate; turning off waits a
  /// minimum dwell so the holding state cannot flicker frame-to-frame near the floor.
  func syncDisplayedHolding(animated: Bool) {
    for kind in LoadAssistKind.allCases {
      let raw = runtime.activeAssistKinds.contains(kind)
      let shown = displayedHolding.contains(kind)
      if raw, !shown {
        holdingReleaseToken[kind, default: 0] += 1
        setDisplayedHolding(kind, to: true, animated: animated)
      } else if !raw, shown {
        holdingReleaseToken[kind, default: 0] += 1
        let token = holdingReleaseToken[kind] ?? 0
        DispatchQueue.main.asyncAfter(
          deadline: .now() + SensorDashboardSidebarConstants.holdingReleaseDelaySeconds
        ) {
          guard self.holdingReleaseToken[kind] == token else { return }
          self.setDisplayedHolding(kind, to: false, animated: true)
        }
      }
    }
  }

  func isDisplayedHolding(_ kind: LoadAssistKind) -> Bool {
    displayedHolding.contains(kind)
  }

  private func setDisplayedHolding(_ kind: LoadAssistKind, to value: Bool, animated: Bool) {
    let mutate = {
      if value {
        self.displayedHolding.insert(kind)
      } else {
        self.displayedHolding.remove(kind)
      }
    }
    if animated {
      withAnimation(
        .easeInOut(duration: SensorDashboardSidebarConstants.holdingCrossfadeDuration)
      ) {
        mutate()
      }
    } else {
      mutate()
    }
  }

  var fanControlToggleBusy: Bool {
    if case .setFanControl = pendingAction { return true }
    return false
  }

  func beginPendingAction(_ action: SidebarPendingAction) {
    pendingAction = action
    pendingActionStartDate = Date()
    sensorDashboardSidebarViewLog.notice(
      "sidebar.pending.started action=\(action.logName, privacy: .public)"
    )
  }

  func reconcilePendingAction(reason: String) {
    guard let pendingAction else { return }
    if pendingActionFailed(pendingAction) {
      guard pendingActionMinimumVisibleDurationElapsed() else {
        logPendingActionMinimumDelay(pendingAction, reason: "\(reason)-failed")
        return
      }
      completePendingAction(pendingAction, reason: "\(reason)-failed")
      return
    }
    if pendingActionObserved(pendingAction) {
      guard pendingActionMinimumVisibleDurationElapsed() else {
        logPendingActionMinimumDelay(pendingAction, reason: "\(reason)-observed")
        return
      }
      completePendingAction(pendingAction, reason: "\(reason)-observed")
    }
  }

  func completePendingAction(_ action: SidebarPendingAction, reason: String) {
    guard pendingAction == action else { return }
    pendingAction = nil
    pendingActionStartDate = nil
    sensorDashboardSidebarViewLog.notice(
      "sidebar.pending.finished action=\(action.logName, privacy: .public) reason=\(reason, privacy: .public)"
    )
  }

  func pendingActionMinimumVisibleDurationElapsed() -> Bool {
    pendingActionMinimumRemainingNanoseconds() == 0
  }

  func pendingActionMinimumRemainingNanoseconds() -> UInt64 {
    guard let pendingAction else { return 0 }
    let minimumDuration = pendingAction.minimumVisibleDuration
    guard minimumDuration > 0 else { return 0 }
    guard let pendingActionStartDate else { return 0 }
    let elapsedDuration = Date().timeIntervalSince(pendingActionStartDate)
    let remainingDuration = minimumDuration - elapsedDuration
    guard remainingDuration > 0 else { return 0 }
    return UInt64(remainingDuration * SensorDashboardSidebarConstants.nanosecondsPerSecond)
  }

  private func logPendingActionMinimumDelay(_ action: SidebarPendingAction, reason: String) {
    sensorDashboardSidebarViewLog.debug(
      "sidebar.pending.minimum_duration.waiting action=\(action.logName, privacy: .public) reason=\(reason, privacy: .public)"
    )
  }

  private func pendingActionObserved(_ action: SidebarPendingAction) -> Bool {
    switch action {
    case .helperSetup:
      return installState.step == .helperAwaitingApproval
        || installState.step == .ready
    case .agentSetup:
      return installState.step != .agentMissing
    case .openSystemSettings:
      return installState.step != .agentAwaitingApproval
        && installState.step != .helperAwaitingApproval
    case .enableBoost:
      return runtime.boostEnabled
    case .disableBoost:
      return !runtime.boostEnabled
    case .setFanControl(let enabled):
      return runtime.curveActive == enabled
    }
  }

  private func pendingActionFailed(_ action: SidebarPendingAction) -> Bool {
    switch action {
    case .helperSetup, .agentSetup, .openSystemSettings:
      return installState.lastError != nil
    case .enableBoost, .disableBoost, .setFanControl:
      return false
    }
  }
}
