//
//  AdvancedSettingsView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026
//

import AppLog
import SwiftUI

private let advancedSettingsLog = AppLog.make(category: "AdvancedSettings")

struct AdvancedSettingsView: View {
    private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

    @AppStorage(SharedConfigKeys.overdriveEnabled, store: suite)
    private var overdrive: Bool = false

    @AppStorage(SharedConfigKeys.underdriveEnabled, store: suite)
    private var underdrive: Bool = false

    @AppStorage(SharedConfigKeys.curveNormalPriority, store: suite)
    private var curveNormalPriority: Double = 10

    @AppStorage(SharedConfigKeys.userBoostPriority, store: suite)
    private var userBoostPriority: Double = 50

    @State private var confirmOverdrive = false
    @State private var confirmUnderdrive = false

    private var overdriveBinding: Binding<Bool> {
        Binding(
            get: { overdrive },
            set: { newValue in
                if newValue { confirmOverdrive = true } else { overdrive = false }
            })
    }

    private var underdriveBinding: Binding<Bool> {
        Binding(
            get: { underdrive },
            set: { newValue in
                if newValue { confirmUnderdrive = true } else { underdrive = false }
            })
    }

    var body: some View {
        ScrollView {
            Form {
                Section {
                    LoadAssistModuleView(kind: .cpu)
                    LoadAssistModuleView(kind: .gpu)
                } header: {
                    Text("Load Assist")
                } footer: {
                    Text(
                        "Each assist curve maps load percent to a minimum fan floor. "
                            + "The agent evaluates the temperature curve, CPU assist, and GPU assist, "
                            + "then applies whichever result is highest."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    prioritySliderRow(
                        title: "Normal curve",
                        value: $curveNormalPriority,
                        help:
                            "Priority used for normal curve writes. Higher values preempt lower-priority fan clients."
                    )
                    prioritySliderRow(
                        title: "When boost is on",
                        value: $userBoostPriority,
                        help:
                            "Priority used while Boost is active. "
                            + "Raise it above competing fan apps if Boost should win."
                    )
                } header: {
                    Text("Client Priority")
                } footer: {
                    Text(
                        "Priority the agent uses when writing fans. Higher values preempt lower. "
                            + "Defaults match other fan aware apps: normal curve at 10, boost at 50. "
                            + "Raise boost above 50 if boost should preempt an active lmd LLM run."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Toggle(isOn: overdriveBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Overdrive")
                            Text(
                                "100% on the curve requests \(Int(overdriveTargetRPM)) RPM. Fans can wear faster."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(isOn: underdriveBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Underdrive")
                            Text(
                                "0% writes 0 RPM in manual mode. Fans can stop completely and the machine can overheat."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label {
                        Text("Expanded Range")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(nsColor: .systemOrange))
                    }
                } footer: {
                    Text(
                        "These modes bypass the firmware reported safe range. "
                            + "Enable them only if you understand the risks."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .alert("Enable Overdrive?", isPresented: $confirmOverdrive) {
            Button("Enable", role: .destructive) { overdrive = true }
            Button("Cancel", role: .cancel) {
                confirmOverdrive = false
            }
        } message: {
            Text(
                "Overdrive pushes fan targets beyond the firmware reported max. "
                    + "Sustained high RPM shortens bearing life and increases noise. "
                    + "Only enable if you accept the tradeoff."
            )
        }
        .alert("Enable Underdrive?", isPresented: $confirmUnderdrive) {
            Button("Enable", role: .destructive) { underdrive = true }
            Button("Cancel", role: .cancel) {
                confirmUnderdrive = false
            }
        } message: {
            Text(
                "Underdrive lets the curve force fans to 0 RPM in manual mode. "
                    + "Without airflow your machine can overheat under load and throttle or shut down. "
                    + "Only enable if you know your thermal limits."
            )
        }
    }

    @ViewBuilder
    private func prioritySliderRow(title: String, value: Binding<Double>, help: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.07))
                    )
            }
            Slider(
                value: Binding(
                    get: { value.wrappedValue },
                    set: { value.wrappedValue = $0.rounded() }
                ),
                in: 1...100
            )
            .help(help)
        }
    }
}

/// Computes SHA256 short fingerprints of the main app and embedded agent
/// binaries. Cached in static properties so the About tab does not
/// re-hash on every render.
enum BuildHashes {
    static let appHash: String = BuildFingerprint.runningExecutableHash
    static let agentHash: String = BuildFingerprint.bundledAgentHash
}
