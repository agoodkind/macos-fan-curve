//
//  GeneralSettingsView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import SwiftUI

let generalSettingsLog = AppLog.make(category: "GeneralSettings")

enum GeneralSettingsConstants {
  // Layout: accessory widths
  static let activeControllersSummaryAccessoryWidth: CGFloat = 144
  static let controllerRowMinimumLabelWidth: CGFloat = 72
  static let controllerRowAccessoryWidth: CGFloat = 260
  static let statusRowAccessoryWidth: CGFloat = 112

  // Layout: spacing
  static let rowHStackSpacing: CGFloat = 8
  static let accessoryHStackSpacing: CGFloat = 6
  static let controllerRowVStackSpacing: CGFloat = 2
  static let helperActionSpacing: CGFloat = 6
  static let helperActionButtonHStackSpacing: CGFloat = 6

  // Layout: indicator dot
  static let indicatorDotSize: CGFloat = 8
  static let indicatorDotVStackSpacing: CGFloat = 2

  // Layout: controller row
  static let controllerRowVerticalPadding: CGFloat = 2

  // Layout: progress view scale
  static let progressViewScale: CGFloat = 0.7

  // Monitoring
  static let ownershipRefreshIntervalSeconds: Double = 5.0

  // Age formatting
  static let ageJustNowThresholdSeconds: Double = 1.0
  static let secondsPerMinute: Double = 60
}

/// General display preferences. Stored in UserDefaults.standard because they
/// only affect the GUI and do not need to be visible to the agent.
struct GeneralSettingsView: View {
  let monitoringGate: SettingsMonitoringGate

  @AppStorage("temperatureUnit") private var unitRaw: String = "celsius"

  private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

  @AppStorage(SharedConfigKeys.applyInBackground, store: suite)
  private var applyInBackground: Bool = true

  @EnvironmentObject var agentClient: FanCurveAgentClient
  @StateObject private var installState = InstallationState()
  @StateObject private var ownershipStatus = FanOwnershipStatus()
  @State private var showOwnership = false
  @State private var isMonitoringActive = false

  var body: some View {
    SettingsFormContainer {
      Section {
        Picker("Temperature Unit", selection: $unitRaw) {
          ForEach(TemperatureUnit.allCases) { unit in
            Text(unit.displayName).tag(unit.rawValue)
          }
        }
        .pickerStyle(.segmented)
      } header: {
        Text("Display")
      } footer: {
        SettingsDescription(text: "Only affects how temperatures are displayed.")
      }

      Section {
        Toggle("Apply curve in background", isOn: applyInBackgroundBinding)
          .accessibilityValue(applyInBackground ? "1" : "0")
          .accessibilityIdentifier(AppAccessibilityIdentifier.Settings.applyInBackground)
      } header: {
        Text("Background Control")
      } footer: {
        SettingsDescription(
          text:
            "When on, the curve keeps controlling fans after you quit the app and resumes on next login. "
            + "When off, quitting returns fans to system auto."
        )
      }

      Section {
        agentRow
        agentAction
      } header: {
        Text("Background Agent")
      } footer: {
        SettingsDescription(
          text:
            "Applies the curve when the app is closed. Resets fans to auto when disabled."
        )
      }

      Section {
        helperRow
        helperAction
        SettingsAnimatedDisclosure(isExpanded: $showOwnership) {
          activeControllersSummary
        } content: {
          activeControllersContent
        }
        .accessibilityIdentifier(AppAccessibilityIdentifier.Settings.ownershipDisclosure)
      } header: {
        Text("Privileged Helper")
      } footer: {
        SettingsDescription(text: activeControllersFooterText)
      }
    }
    .onAppear {
      refreshInstallationState(reason: "appear")
      updateMonitoringState()
    }
    .onChange(of: monitoringGate) { _ in
      updateMonitoringState()
    }
    .onChange(of: agentClient.connectionState) { _ in
      refreshInstallationState(reason: "agent-connection-changed")
    }
    .onChange(of: agentClient.helperReachable) { _ in
      refreshInstallationState(reason: "helper-reachability-changed")
    }
    .onDisappear {
      setMonitoring(active: false)
    }
  }

  private func refreshInstallationState(reason: String) {
    generalSettingsLog.info(
      "general_settings.installation.refresh_requested reason=\(reason, privacy: .public)"
    )
    agentClient.start()
    Task {
      installState.refreshOnce(agentClient: agentClient)
      await ownershipStatus.refreshOnce(agentClient: agentClient)
    }
  }

  private func updateMonitoringState() {
    setMonitoring(active: monitoringGate.isMonitoringEnabled)
  }

  private func setMonitoring(active: Bool) {
    guard active != isMonitoringActive else { return }
    isMonitoringActive = active

    generalSettingsLog.info(
      "general_settings.monitoring.changed enabled=\(active, privacy: .public) tab=\(String(describing: monitoringGate.selectedTab), privacy: .public) render_mode=\(String(describing: monitoringGate.renderMode), privacy: .public)"
    )

    if active {
      agentClient.start()
      installState.startMonitoring(agentClient: agentClient)
      ownershipStatus.startMonitoring(
        agentClient: agentClient,
        intervalSeconds: GeneralSettingsConstants.ownershipRefreshIntervalSeconds)
    } else {
      installState.stopMonitoring()
      ownershipStatus.stopMonitoring()
    }
  }

  private var applyInBackgroundBinding: Binding<Bool> {
    Binding(
      get: { applyInBackground },
      set: { enabled in
        generalSettingsLog.info(
          "general_settings.apply_in_background.toggled enabled=\(enabled, privacy: .public)"
        )
        Task {
          do {
            try await agentClient.setApplyInBackground(enabled)
            await MainActor.run {
              applyInBackground = enabled
            }
          } catch {
            generalSettingsLog.notice(
              "general_settings.apply_in_background.command_failed enabled=\(enabled, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=keep-current-state"
            )
          }
        }
      }
    )
  }

  var activeControllersSummary: some View {
    SettingsAccessoryRow(
      accessoryWidth: GeneralSettingsConstants.activeControllersSummaryAccessoryWidth
    ) {
      Text("Active Controllers")
        .fontWeight(.semibold)
        .lineLimit(1)
    } accessory: {
      HStack(spacing: GeneralSettingsConstants.accessoryHStackSpacing) {
        if ownershipStatus.isMonitoring, !ownershipStatus.hasLoaded {
          ProgressView()
            .controlSize(.small)
            .scaleEffect(GeneralSettingsConstants.progressViewScale)
        }
        Text(activeControllersStatusText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .accessibilityIdentifier(AppAccessibilityIdentifier.Settings.ownershipStatus)
      }
    }
  }

  var activeControllersStatusText: String {
    let count = ownershipStatus.rows.count
    if ownershipStatus.isMonitoring, !ownershipStatus.hasLoaded { return "Checking" }
    if !activeControllersReachable { return "Helper unreachable" }
    if !ownershipStatus.hasLoaded { return "Checking" }
    if count == 0 { return "No controllers" }
    if count == 1 { return "1 fan active" }
    return "\(count) fans active"
  }

  private var activeControllersReachable: Bool {
    ownershipStatus.reachable || installState.helperReachable
  }

  @ViewBuilder
  var activeControllersContent: some View {
    if ownershipStatus.isMonitoring, !ownershipStatus.hasLoaded {
      Text("Checking helper...")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else if ownershipStatus.rows.isEmpty {
      Text(activeControllersEmptyText)
        .font(.caption)
        .foregroundStyle(.secondary)
    } else {
      ForEach(ownershipStatus.rows) { row in
        activeControllerRow(row)
      }
    }
  }

  private var activeControllersEmptyText: String {
    activeControllersReachable ? "No fan controllers are active." : "Waiting for helper."
  }

  var activeControllersFooterText: String {
    "Shows which app or service is currently controlling each fan. "
      + "If another controller has higher priority, Fan Curve may wait before applying changes."
  }

}

extension GeneralSettingsView {
  private func statusRow(
    title: String,
    subtitle: String,
    status: String,
    state: ServiceRowState
  ) -> some View {
    SettingsAccessoryRow(accessoryWidth: GeneralSettingsConstants.statusRowAccessoryWidth) {
      HStack(
        alignment: .firstTextBaseline, spacing: GeneralSettingsConstants.rowHStackSpacing
      ) {
        Circle()
          .fill(state.color)
          .frame(
            width: GeneralSettingsConstants.indicatorDotSize,
            height: GeneralSettingsConstants.indicatorDotSize)
        VStack(
          alignment: .leading, spacing: GeneralSettingsConstants.indicatorDotVStackSpacing
        ) {
          Text(title)
            .font(.body)
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    } accessory: {
      Text(status)
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier(AppAccessibilityIdentifier.Settings.helperStatus)
    }
  }

  private var helperRow: some View {
    statusRow(
      title: generatedHelperDisplayName,
      subtitle: generatedHelperBundleID,
      status: helperStatusText,
      state: helperRowState
    )
    .accessibilityIdentifier(AppAccessibilityIdentifier.Settings.helperRow)
  }

  @ViewBuilder
  private var helperAction: some View {
    let showsHelperRepairAction =
      agentClient.connectionState == .connected
      && (installState.helperNeedsRepair
        || !installState.helperEnabled
        || !installState.helperReachable)
    if showsHelperRepairAction {
      VStack(alignment: .leading, spacing: GeneralSettingsConstants.helperActionSpacing) {
        Button {
          performHelperAction()
        } label: {
          HStack(spacing: GeneralSettingsConstants.helperActionButtonHStackSpacing) {
            if installState.isRegisteringHelper {
              ProgressView()
                .controlSize(.small)
                .scaleEffect(GeneralSettingsConstants.progressViewScale)
            }
            Text(helperActionTitle)
          }
        }
        .disabled(installState.isRegisteringHelper)
        .controlSize(.small)
        .accessibilityIdentifier(AppAccessibilityIdentifier.Settings.helperAction)

        if installState.helperNeedsRepair {
          SettingsDescription(
            text: helperRepairDescription
          )
        }
      }
    }
  }

  private var agentRow: some View {
    SettingsAccessoryRow(accessoryWidth: GeneralSettingsConstants.statusRowAccessoryWidth) {
      HStack(
        alignment: .firstTextBaseline, spacing: GeneralSettingsConstants.rowHStackSpacing
      ) {
        Circle()
          .fill(agentRowState.color)
          .frame(
            width: GeneralSettingsConstants.indicatorDotSize,
            height: GeneralSettingsConstants.indicatorDotSize)
        VStack(
          alignment: .leading, spacing: GeneralSettingsConstants.indicatorDotVStackSpacing
        ) {
          Text(generatedAgentDisplayName)
            .font(.body)
          Text(generatedAgentBundleID)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    } accessory: {
      HStack(spacing: GeneralSettingsConstants.accessoryHStackSpacing) {
        if installState.isRegisteringAgent {
          ProgressView()
            .controlSize(.small)
            .scaleEffect(GeneralSettingsConstants.progressViewScale)
        }
        Text(agentStatusText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier(AppAccessibilityIdentifier.Settings.backgroundAgentStatus)
      }
    }
    .accessibilityIdentifier(AppAccessibilityIdentifier.Settings.backgroundAgentRow)
  }

  private var helperRowState: ServiceRowState {
    if installState.helperNeedsRepair || installState.helperApprovalPending { return .degraded }
    if installState.helperEnabled, installState.helperReachable { return .healthy }
    if installState.helperReachable { return .degraded }
    return .inactive
  }

  private var helperStatusText: String {
    if installState.helperNeedsRepair { return "Reachable, registration needs repair" }
    if installState.helperApprovalPending { return "Awaiting approval" }
    if installState.helperEnabled, installState.helperReachable { return "Running" }
    if installState.helperEnabled { return "Installed" }
    return "Not Installed"
  }

  private var helperActionTitle: String {
    if installState.helperApprovalPending {
      return "Open System Settings"
    }
    if installState.isRegisteringHelper {
      return installState.helperNeedsRepair
        ? "Reinstalling System Helper"
        : "Installing System Helper"
    }
    return installState.helperNeedsRepair ? "Reinstall System Helper" : "Install System Helper"
  }

  private var helperRepairDescription: String {
    "Fan Curve can still reach the System Helper, but this app install needs to "
      + "repair its helper registration."
  }

  private func performHelperAction() {
    if installState.helperApprovalPending {
      generalSettingsLog.info("general_settings.helper.approval.tapped owner=agent-xpc")
      Task {
        do {
          try await agentClient.openSystemSettings()
        } catch {
          generalSettingsLog.notice(
            "general_settings.helper.approval.failed error=\(error.localizedDescription, privacy: .public) recovery=show-agent-command-error"
          )
          await MainActor.run {
            installState.lastError = error.localizedDescription
          }
        }
      }
      return
    }

    generalSettingsLog.info("general_settings.helper.install.tapped owner=agent-xpc")
    installState.installOrRepairHelper(agentClient: agentClient)
  }

  private var agentRowState: ServiceRowState {
    if installState.agentLive { return .healthy }
    if installState.agentEnabled { return .degraded }
    return .inactive
  }

  @ViewBuilder
  private var agentAction: some View {
    if installState.agentEnabled, !installState.agentLive {
      Button("Restart") { restartAgent() }
        .controlSize(.small)
        .accessibilityIdentifier(AppAccessibilityIdentifier.Settings.backgroundAgentAction)
    } else if !installState.agentEnabled {
      Button {
        generalSettingsLog.info("general_settings.agent.install.tapped")
        installState.registerAgent()
      } label: {
        HStack(spacing: GeneralSettingsConstants.helperActionButtonHStackSpacing) {
          if installState.isRegisteringAgent {
            ProgressView()
              .controlSize(.small)
              .scaleEffect(GeneralSettingsConstants.progressViewScale)
          }
          Text(
            installState.isRegisteringAgent
              ? "Enabling Background Control"
              : "Enable Background Control"
          )
        }
      }
      .disabled(installState.isRegisteringAgent)
      .controlSize(.small)
      .accessibilityIdentifier(AppAccessibilityIdentifier.Settings.backgroundAgentAction)
    }
  }

  private var agentStatusText: String {
    if installState.agentLive { return "Running" }
    if installState.agentEnabled { return "Installed" }
    return "Not Installed"
  }

  private func restartAgent() {
    generalSettingsLog.info("general_settings.agent.restart.tapped")
    installState.unregisterAgent()
    installState.registerAgent()
  }
}
