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

    @AppStorage(SharedConfigKeys.fanResponseValue, store: suite)
    private var fanResponseValue: Double = FanResponse.defaultValue

    @AppStorage(SharedConfigKeys.inferFanResponseFromGraph, store: suite)
    private var inferFanResponseFromGraph: Bool = FanResponse.defaultInferFromGraph

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
        SettingsFormContainer {
            fanResponseSection
            loadAssistSection
            prioritySection
            dangerZoneSection
        }
        .alert("Enable Overdrive?", isPresented: $confirmOverdrive) {
            Button("Enable", role: .destructive) {
                advancedSettingsLog.notice("advanced_settings.overdrive.confirmed enabled=true")
                overdrive = true
            }
            Button("Cancel", role: .cancel) {
                confirmOverdrive = false
            }
        } message: {
            Text(overdriveWarningText)
        }
        .alert("Enable Underdrive?", isPresented: $confirmUnderdrive) {
            Button("Enable", role: .destructive) {
                advancedSettingsLog.notice("advanced_settings.underdrive.confirmed enabled=true")
                underdrive = true
            }
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
            SettingsDescription(text: loadAssistFooterText)
        }
    }

    private var fanResponseSection: some View {
        Section {
            SettingsToggleDescriptionRow(
                title: "Infer from graph",
                description: inferFanResponseDescription,
                isOn: $inferFanResponseFromGraph
            )
            SettingsSliderRow(
                title: inferFanResponseFromGraph ? "Response Bias" : "Response",
                description: fanResponseDescription,
                displayValue: responseDisplayText,
                value: fanResponseBinding,
                range: 0...1,
                scaleLabels: SettingsSliderScaleLabels(
                    minimum: "Smoother",
                    maximum: "Faster",
                    midpoint: "Balanced"
                )
            )
        } header: {
            Text("Fan Response")
        } footer: {
            SettingsDescription(text: fanResponseFooterText)
        }
    }

    private var prioritySection: some View {
        Section {
            SettingsSliderRow(
                title: "Normal curve",
                description: "Priority used for regular curve writes when Boost is off.",
                displayValue: "\(Int(curveNormalPriority.rounded()))",
                value: priorityBinding($curveNormalPriority),
                range: 1...100,
                step: 1,
                scaleLabels: SettingsSliderScaleLabels(minimum: "Low", maximum: "High"),
                help:
                    "Priority used for normal curve writes. Higher values preempt lower-priority fan clients."
            )
            SettingsSliderRow(
                title: "When boost is on",
                description: "Priority used while Boost is active.",
                displayValue: "\(Int(userBoostPriority.rounded()))",
                value: priorityBinding($userBoostPriority),
                range: 1...100,
                step: 1,
                scaleLabels: SettingsSliderScaleLabels(minimum: "Low", maximum: "High"),
                help:
                    "Priority used while Boost is active. Raise it above competing fan apps if Boost should win."
            )
        } header: {
            Text("Client Priority")
        } footer: {
            SettingsDescription(text: priorityFooterText)
        }
    }

    private var dangerZoneSection: some View {
        Section {
            SettingsDangerDisclosure(
                title: "Expanded Range",
                status: expandedRangeStatus
            ) {
                SettingsDangerToggleRow(
                    title: "Overdrive",
                    description:
                        "Allows curve points to request up to \(Int(overdriveTargetRPM)) RPM.",
                    isOn: overdriveBinding
                )

                SettingsDangerToggleRow(
                    title: "Underdrive",
                    description: "Allows 0% curve points to stop fans in manual mode.",
                    isOn: underdriveBinding
                )
            }
        } header: {
            Text("Fan Range Limits")
        } footer: {
            SettingsDescription(text: expandedRangeDisclosureText)
        }
    }

    private var fanResponseBinding: Binding<Double> {
        Binding(
            get: { FanResponse(value: fanResponseValue).value },
            set: { fanResponseValue = FanResponse(value: $0).value }
        )
    }

    private func priorityBinding(_ value: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = $0.rounded() }
        )
    }

    private var loadAssistFooterText: String {
        "Each assist curve maps load percent to a minimum fan floor. "
            + "The agent evaluates the temperature curve, CPU assist, and GPU assist, "
            + "then applies whichever result is highest."
    }

    private var inferFanResponseDescription: String {
        "Uses curve steepness near the current temperature to choose a gentler or faster fan response."
    }

    private var fanResponseDescription: String {
        if inferFanResponseFromGraph {
            return "Biases graph inference toward smoother or faster response."
        }

        return "Sets how quickly acoustic damping lets fan commands change."
    }

    private var fanResponseFooterText: String {
        "Controls how quickly acoustic damping lets fan commands change. "
            + "Lower values favor quieter transitions; higher values follow curve changes more directly."
    }

    private var priorityFooterText: String {
        "Priority the agent uses when writing fans. Higher values preempt lower. "
            + "Defaults match other fan aware apps: normal curve at 10, boost at 50. "
            + "Raise boost above 50 if boost should preempt an active lmd LLM run."
    }

    private var expandedRangeDisclosureText: String {
        "Allows fan targets outside the firmware reported safe range. "
            + "Overdrive can increase noise and wear; underdrive can reduce cooling under load."
    }

    private var expandedRangeStatus: String? {
        switch (overdrive, underdrive) {
        case (true, true):
            return "Both On"
        case (true, false):
            return "Overdrive On"
        case (false, true):
            return "Underdrive On"
        case (false, false):
            return nil
        }
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

    private var responseDisplayText: String {
        "\(Int(FanResponse(value: fanResponseValue).value * 100))%"
    }
}
