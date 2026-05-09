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
            }
        )
    }

    private var underdriveBinding: Binding<Bool> {
        Binding(
            get: { underdrive },
            set: { newValue in
                if newValue { confirmUnderdrive = true } else { underdrive = false }
            }
        )
    }

    var body: some View {
        ScrollView {
            Form {
                loadAssistSection
                prioritySection
                expandedRangeSection
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
            Text(overdriveWarningText)
        }
        .alert("Enable Underdrive?", isPresented: $confirmUnderdrive) {
            Button("Enable", role: .destructive) { underdrive = true }
            Button("Cancel", role: .cancel) {
                confirmUnderdrive = false
            }
        } message: {
            Text(underdriveWarningText)
        }
    }

    private var loadAssistSection: some View {
        Section {
            LoadAssistModuleView(kind: .cpu)
            LoadAssistModuleView(kind: .gpu)
        } header: {
            Text("Load Assist")
        } footer: {
            Text(loadAssistFooterText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var prioritySection: some View {
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
                    "Priority used while Boost is active. Raise it above competing fan apps if Boost should win."
            )
        } header: {
            Text("Client Priority")
        } footer: {
            Text(priorityFooterText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var expandedRangeSection: some View {
        Section {
            Toggle(isOn: overdriveBinding) {
                rangeToggleContent(
                    title: "Overdrive",
                    detail: "100% on the curve requests \(Int(overdriveTargetRPM)) RPM. Fans can wear faster."
                )
            }

            Toggle(isOn: underdriveBinding) {
                rangeToggleContent(
                    title: "Underdrive",
                    detail: "0% writes 0 RPM in manual mode. Fans can stop completely and the machine can overheat."
                )
            }
        } header: {
            Label {
                Text("Expanded Range")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(nsColor: .systemOrange))
            }
        } footer: {
            Text(expandedRangeFooterText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func rangeToggleContent(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var loadAssistFooterText: String {
        "Each assist curve maps load percent to a minimum fan floor. "
            + "The agent evaluates the temperature curve, CPU assist, and GPU assist, "
            + "then applies whichever result is highest."
    }

    private var priorityFooterText: String {
        "Priority the agent uses when writing fans. Higher values preempt lower. "
            + "Defaults match other fan aware apps: normal curve at 10, boost at 50. "
            + "Raise boost above 50 if boost should preempt an active lmd LLM run."
    }

    private var expandedRangeFooterText: String {
        "These modes bypass the firmware reported safe range. "
            + "Enable them only if you understand the risks."
    }

    private var overdriveWarningText: String {
        "Overdrive pushes fan targets beyond the firmware reported max. "
            + "Sustained high RPM shortens bearing life and increases noise. "
            + "Only enable if you accept the tradeoff."
    }

    private var underdriveWarningText: String {
        "Underdrive lets the curve force fans to 0 RPM in manual mode. "
            + "Without airflow your machine can overheat under load and throttle or shut down. "
            + "Only enable if you know your thermal limits."
    }
}
