//
//  GeneralSettingsView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026
//

import AppLog
import SwiftUI

private let generalSettingsLog = AppLog.make(category: "GeneralSettings")

/// General display preferences. Stored in UserDefaults.standard because they
/// only affect the GUI and do not need to be visible to the agent.
struct GeneralSettingsView: View {
    @AppStorage("temperatureUnit") private var unitRaw: String = "celsius"

    private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

    @AppStorage(SharedConfigKeys.applyInBackground, store: suite)
    private var applyInBackground: Bool = true

    @EnvironmentObject var agentClient: FanCurveAgentClient
    @StateObject private var installState = InstallationState()
    @StateObject private var ownershipStatus = FanOwnershipStatus()
    @State private var showOwnership = false

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
            } header: {
                Text("Background Control")
            } footer: {
                SettingsDescription(
                    text: "When on, the curve keeps controlling fans after you quit the app and resumes on next login. "
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
                    text: "Applies the curve when the app is closed. Resets fans to auto when disabled."
                )
            }

            Section {
                helperRow
                helperAction
                DisclosureGroup(isExpanded: $showOwnership) {
                    ownershipContent
                } label: {
                    ownershipSummary
                }
            } header: {
                Text("Privileged Helper")
            } footer: {
                SettingsDescription(
                    text: "Runs as root to read and write SMC fan keys."
                )
            }
        }
        .onAppear {
            agentClient.start()
            installState.startMonitoring(agentClient: agentClient)
            ownershipStatus.startMonitoring(agentClient: agentClient, intervalSeconds: 1.5)
        }
        .onDisappear {
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

    private var ownershipSummary: some View {
        SettingsAccessoryRow(accessoryWidth: 132) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Current Owners")
                SettingsDescription(text: "Active fan writers by priority.")
            }
        } accessory: {
            HStack(spacing: 6) {
                if ownershipStatus.isMonitoring, !ownershipStatus.hasLoaded {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
                Text(ownershipStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ownershipStatusText: String {
        let count = ownershipStatus.rows.count
        if ownershipStatus.isMonitoring, !ownershipStatus.hasLoaded { return "Checking" }
        if !ownershipStatus.reachable { return "Helper unreachable" }
        if count == 0 { return "No fans claimed" }
        return "\(count) claimed"
    }

    @ViewBuilder
    private var ownershipContent: some View {
        if ownershipStatus.isMonitoring, !ownershipStatus.hasLoaded {
            Text("Checking helper...")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if ownershipStatus.rows.isEmpty {
            Text(ownershipStatus.reachable ? "No fans currently claimed." : "Waiting for helper.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(ownershipStatus.rows) { row in
                ownershipRow(row)
            }
        }
    }

    @ViewBuilder
    private func ownershipRow(_ row: AgentOwnershipEntry) -> some View {
        SettingsAccessoryRow(accessoryWidth: 132) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fan \(row.fanIndex)")
                    .font(.caption)
                Text("owned by \(row.clientName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } accessory: {
            VStack(alignment: .trailing, spacing: 2) {
                Text("priority \(row.priority)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(formatAge(row.ageSeconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatAge(_ seconds: TimeInterval) -> String {
        if seconds < 1.0 { return "just now" }
        if seconds < 60 { return "\(Int(seconds))s ago" }
        let minutes = Int(seconds / 60)
        return "\(minutes)m ago"
    }

    private func statusRow(title: String, subtitle: String, status: String, state: ServiceRowState) -> some View {
        SettingsAccessoryRow(accessoryWidth: 112) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(state.color)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
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
        }
    }

    private var helperRow: some View {
        statusRow(
            title: generatedHelperDisplayName,
            subtitle: generatedHelperBundleID,
            status: helperStatusText,
            state: helperRowState
        )
    }

    @ViewBuilder
    private var helperAction: some View {
        if !installState.helperEnabled || !installState.helperReachable {
            Button {
                generalSettingsLog.info("general_settings.helper.install.tapped")
                installState.registerHelperDaemon(agentClient: agentClient)
            } label: {
                HStack(spacing: 6) {
                    if installState.isRegisteringHelper {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                    Text(installState.isRegisteringHelper ? "Installing" : "Install")
                }
            }
            .disabled(installState.isRegisteringHelper)
            .controlSize(.small)
        }
    }

    private var agentRow: some View {
        SettingsAccessoryRow(accessoryWidth: 112) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(agentRowState.color)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(generatedAgentDisplayName)
                        .font(.body)
                    Text(generatedAgentBundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } accessory: {
            HStack(spacing: 6) {
                if installState.isRegisteringAgent {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
                Text(agentStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var helperRowState: ServiceRowState {
        if installState.helperEnabled, installState.helperReachable { return .healthy }
        if installState.helperReachable { return .degraded }
        return .inactive
    }

    private var helperStatusText: String {
        if installState.helperEnabled, installState.helperReachable { return "Running" }
        if installState.helperEnabled { return "Installed" }
        if installState.helperReachable { return "Needs Reinstall" }
        return "Not Installed"
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
        } else if !installState.agentEnabled {
            Button {
                generalSettingsLog.info("general_settings.agent.install.tapped")
                installState.registerAgent()
            } label: {
                HStack(spacing: 6) {
                    if installState.isRegisteringAgent {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                    Text(installState.isRegisteringAgent ? "Installing" : "Install")
                }
            }
            .disabled(installState.isRegisteringAgent)
            .controlSize(.small)
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
