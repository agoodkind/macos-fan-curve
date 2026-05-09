//
//  ProfilesSettingsView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026
//

import AppLog
import SwiftUI

private let settingsViewLog = AppLog.make(category: "SettingsView")

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

    var body: some View {
        ScrollView {
            formBody
        }
        .sheet(isPresented: $showLearnSheet, onDismiss: stopPreviewPoller) {
            LearnSheet(curveModel: curveModel, sensorState: sensorState)
                .onAppear(perform: startPreviewPoller)
        }
    }

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

    private func startPreviewPoller() {
        let controller = FanCurveController(xpcClient: xpcClient, sensorState: sensorState)
        previewController = controller
        controller.start()
    }

    private func stopPreviewPoller() {
        previewController?.stop()
        previewController = nil
    }
}
