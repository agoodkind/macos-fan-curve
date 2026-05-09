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

    @EnvironmentObject var xpcClient: XPCClient
    @StateObject private var installState = InstallationState()
    @StateObject private var ownershipStatus = FanOwnershipStatus()
    @State private var showOwnership = false

    var body: some View {
        Form {
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
                Text("Only affects how temperatures are displayed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Apply curve in background", isOn: $applyInBackground)
            } header: {
                Text("Background Control")
            } footer: {
                Text(
                    "When on, the curve keeps controlling fans after you quit the app and resumes on next login. "
                        + "When off, quitting returns fans to system auto."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                agentRow
                agentAction
            } header: {
                Text("Background Agent")
            } footer: {
                Text("Applies the curve when the app is closed. Resets fans to auto when disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                helperRow
                DisclosureGroup(isExpanded: $showOwnership) {
                    ownershipContent
                } label: {
                    ownershipSummary
                }
            } header: {
                Text("Privileged Helper")
            } footer: {
                Text(
                    "Reads and writes SMC keys as root. Required for fan control. "
                        + "The helper arbitrates between fan writers by priority; current owners show above."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            installState.startMonitoring(xpcClient: xpcClient)
            ownershipStatus.startMonitoring(intervalSeconds: 1.5)
        }
        .onDisappear {
            installState.stopMonitoring()
            ownershipStatus.stopMonitoring()
        }
    }

    private var ownershipSummary: some View {
        HStack(spacing: 8) {
            Text(ownershipSummaryText)
                .font(.caption)
            if ownershipStatus.isMonitoring, !ownershipStatus.hasLoaded {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }
        }
    }

    private var ownershipSummaryText: String {
        let count = ownershipStatus.rows.count
        if ownershipStatus.isMonitoring, !ownershipStatus.hasLoaded { return "Current Owners" }
        if !ownershipStatus.reachable { return "Current Owners (helper unreachable)" }
        if count == 0 { return "Current Owners (no fans claimed)" }
        return "Current Owners (\(count) claimed)"
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
    private func ownershipRow(_ row: ArbiterRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fan \(row.fanIndex)")
                    .font(.caption)
                Text("owned by \(row.clientName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
        HStack {
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
            Spacer()
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var helperRow: some View {
        statusRow(
            title: "SMC Fan Helper",
            subtitle: generatedHelperBundleID,
            status: installState.helperReachable ? "Running" : "Stopped",
            state: helperRowState
        )
    }

    private var agentRow: some View {
        HStack {
            Circle()
                .fill(agentRowState.color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("Fan Curve Agent")
                    .font(.body)
                Text(generatedAgentBundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
        installState.helperReachable ? .healthy : .inactive
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
