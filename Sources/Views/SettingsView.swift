//
//  SettingsView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import AppKit
import AppLog
import ServiceManagement
import SwiftUI

private let log = AppLog.make(category: "SettingsView")

/// Root Settings window. Uses the macOS Settings scene (Cmd-comma).
/// Three tabs ordered by how often a user reaches for them. Profiles is
/// the hero since it holds the curve itself. General covers everything
/// that runs outside the foreground app. About carries meta information.
struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tag(SettingsTab.general)
                .tabItem { Label("General", systemImage: "gearshape") }
            ProfilesSettingsView()
                .tag(SettingsTab.profiles)
                .tabItem { Label("Profiles", systemImage: "chart.xyaxis.line") }
            AdvancedSettingsView()
                .tag(SettingsTab.advanced)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            AboutSettingsView()
                .tag(SettingsTab.about)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 520, minHeight: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            selectedTab = .general
        }
    }
}

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
        statusRow(
            title: "Fan Curve Agent",
            subtitle: generatedAgentBundleID,
            status: agentStatusText,
            state: agentRowState
        )
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
            Button("Install") { installState.registerAgent() }
                .controlSize(.small)
        }
    }

    private var agentStatusText: String {
        if installState.agentLive { return "Running" }
        if installState.agentEnabled { return "Installed" }
        return "Not Installed"
    }

    /// Unregister then register the agent to force a fresh launch. macOS
    /// launchd will not relaunch a crashed SMAppService.agent on its own;
    /// only re-registration starts a new process.
    private func restartAgent() {
        installState.unregisterAgent()
        installState.registerAgent()
    }

    /// Three-state dot for the Agent. Green when live, orange when
    /// registered but not ticking (fan control is effectively dead), gray
    /// when unregistered.
    @ViewBuilder
    private var agentStatusDot: some View {
        let color: Color = {
            if installState.agentLive { return Color(nsColor: .systemGreen) }
            if installState.agentEnabled { return Color(nsColor: .systemOrange) }
            return Color(nsColor: .systemGray)
        }()
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    @ViewBuilder
    private func statusDot(ok: Bool) -> some View {
        Circle()
            .fill(ok ? Color(nsColor: .systemGreen) : Color(nsColor: .systemGray))
            .frame(width: 8, height: 8)
    }
}

/// Curve behavior settings. These live in the shared suite because the Agent
/// reads the same values when evaluating the curve in the background.
struct ProfilesSettingsView: View {
    @EnvironmentObject var curveModel: FanCurveModel
    @StateObject private var sensorState = SensorState()
    @EnvironmentObject var xpcClient: XPCClient

    @State private var showLearnSheet = false
    @State private var previewController: FanCurveController?

    private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

    @AppStorage(SharedConfigKeys.interpolationMode, store: suite)
    private var interpolationRaw: String = "catmullRom"

    @ViewBuilder
    private func presetRow(_ preset: CurvePreset) -> some View {
        Button {
            curveModel.replaceCurve(preset.curvePoints())
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(preset.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        ScrollView {
            formBody
        }
        .sheet(isPresented: $showLearnSheet, onDismiss: stopPreviewPoller) {
            LearnSheet(curveModel: curveModel, sensorState: sensorState)
                .onAppear(perform: startPreviewPoller)
        }
    }

    private var formBody: some View {
        Form {
            Section {
                Picker("Interpolation", selection: $interpolationRaw) {
                    Text("Linear").tag("linear")
                    Text("Smooth").tag("catmullRom")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Smoothing")
            } footer: {
                Text("Linear draws straight segments between points. Smooth uses monotone cubic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(CurvePresets.all) { preset in
                    presetRow(preset)
                }
            } header: {
                Text("Presets")
            } footer: {
                Text(
                    "Applying a preset replaces your current curve. You can edit the points again afterward."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    log.info(
                        "curve.reset.tapped pointsBefore=\(curveModel.controlPoints.count, privacy: .public)")
                    curveModel.resetToDefault()
                    log.info(
                        "curve.reset.done pointsAfter=\(curveModel.controlPoints.count, privacy: .public)")
                } label: {
                    Label("Reset to Default Curve", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Reset")
            } footer: {
                Text("Replaces the current curve with the built-in starting curve.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    showLearnSheet = true
                } label: {
                    Label("Learn from Current System", systemImage: "brain.head.profile")
                }
            } header: {
                Text("Learn")
            } footer: {
                Text(
                    "Samples your machine under load and fits a curve that mirrors how macOS runs it in Auto mode."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
    }

    /// Spin up a read-only sensor poller so the LearnSheet can display live
    /// temperatures and fan RPMs while sampling.
    private func startPreviewPoller() {
        let ctrl = FanCurveController(xpcClient: xpcClient, sensorState: sensorState)
        previewController = ctrl
        ctrl.start()
    }

    private func stopPreviewPoller() {
        previewController?.stop()
        previewController = nil
    }
}

/// About the app. Checks the GitHub releases API for the latest tag and
/// shows author links. Formerly called "Updates".
