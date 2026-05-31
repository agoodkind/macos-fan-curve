//
//  ProfilesSettingsView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import SwiftUI

private let settingsViewLog = AppLog.make(category: "SettingsView")

private enum PresetRowConstants {
    static let accessoryWidth: CGFloat = 18
    static let titleSubtitleSpacing: CGFloat = 2
}

/// Curve behavior settings. These live in the shared suite because the Agent
/// reads the same values when evaluating the curve in the background.
struct ProfilesSettingsView: View {
    @EnvironmentObject var curveModel: FanCurveModel
    @EnvironmentObject var agentClient: FanCurveAgentClient
    @StateObject private var sensorState = SensorState()

    @State private var showLearnSheet = false

    private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

    @AppStorage(SharedConfigKeys.interpolationMode, store: suite)
    private var interpolationRaw: String = "catmullRom"

    var body: some View {
        SettingsFormContainer {
            formBody
        }
        .sheet(isPresented: $showLearnSheet, onDismiss: stopPreviewPoller) {
            LearnSheet(curveModel: curveModel, sensorState: sensorState)
                .environmentObject(agentClient)
                .onAppear(perform: startPreviewPoller)
        }
        .onChange(of: agentClient.snapshot) { snapshot in
            apply(snapshot: snapshot)
        }
    }

    @ViewBuilder
    private func presetRow(_ preset: CurvePreset) -> some View {
        Button {
            curveModel.replaceCurve(preset.curvePoints())
        } label: {
            SettingsAccessoryRow(accessoryWidth: PresetRowConstants.accessoryWidth) {
                VStack(alignment: .leading, spacing: PresetRowConstants.titleSubtitleSpacing) {
                    Text(preset.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(preset.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } accessory: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var formBody: some View {
        Section {
            Picker("Interpolation", selection: $interpolationRaw) {
                Text("Linear").tag("linear")
                Text("Smooth").tag("catmullRom")
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Smoothing")
        } footer: {
            SettingsDescription(
                text: "Linear draws straight segments between points. Smooth uses monotone cubic."
            )
        }

        Section {
            ForEach(CurvePresets.all) { preset in
                presetRow(preset)
            }
        } header: {
            Text("Presets")
        } footer: {
            SettingsDescription(
                text:
                    "Applying a preset replaces your current curve. You can edit the points again afterward."
            )
        }

        Section {
            Button {
                settingsViewLog.info(
                    "curve.reset.tapped pointsBefore=\(curveModel.controlPoints.count, privacy: .public)"
                )
                curveModel.resetToDefault()
                settingsViewLog.info(
                    "curve.reset.done pointsAfter=\(curveModel.controlPoints.count, privacy: .public)"
                )
            } label: {
                Label("Reset to Default Curve", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Reset")
        } footer: {
            SettingsDescription(
                text: "Replaces the current curve with the built-in starting curve.")
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
            SettingsDescription(
                text:
                    "Samples your machine under load and fits a curve that mirrors how macOS runs it in Auto mode."
            )
        }
    }

    private func startPreviewPoller() {
        agentClient.start()
        apply(snapshot: agentClient.snapshot)
    }

    private func stopPreviewPoller() {
        settingsViewLog.debug("learn.preview.stop recovery=agent-client-remains-shared")
    }

    private func apply(snapshot: AgentSnapshot?) {
        guard let snapshot else { return }
        sensorState.governingTemperature = snapshot.governingTemperatureC
        sensorState.fans = snapshot.fans.map { fan in
            FanReading(
                id: fan.index,
                actualRPM: fan.actualRPM,
                minRPM: fan.minRPM,
                maxRPM: fan.maxRPM
            )
        }
        sensorState.lastUpdate = snapshot.timestamp
    }
}
