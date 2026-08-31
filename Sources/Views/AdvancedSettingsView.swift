//
//  AdvancedSettingsView.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

struct AdvancedSettingsView: View {
  private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

  @AppStorage(SharedConfigKeys.extendedRangeConfigurationAllowed, store: suite)
  private var extendedRangeConfigurationAllowed: Bool = false

  @AppStorage(SharedConfigKeys.curveNormalPriority, store: suite)
  private var curveNormalPriority: Double = 10

  @AppStorage(SharedConfigKeys.userBoostPriority, store: suite)
  private var userBoostPriority: Double = 50

  @AppStorage(SharedConfigKeys.fanResponseValue, store: suite)
  private var fanResponseValue: Double = FanResponse.defaultValue

  @AppStorage(SharedConfigKeys.inferFanResponseFromGraph, store: suite)
  private var inferFanResponseFromGraph: Bool = FanResponse.defaultInferFromGraph

  var body: some View {
    SettingsFormContainer {
      fanResponseSection
      loadAssistSection
      prioritySection
      extendedRangeConfigurationSection
    }
    .onAppear {
      ExpandedRangeConfigurationStore.migrateIfNeeded(defaults: Self.suite)
    }
  }

  private var loadAssistSection: some View {
    Section {
      LoadAssistModuleView(kind: .cpu)
      LoadAssistModuleView(kind: .gpu)
    } header: {
      Text("Load Assist")
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

  private var extendedRangeConfigurationSection: some View {
    Section {
      SettingsToggleDescriptionRow(
        title: "Allow configuring extended ranges",
        description:
          "Shows Overdrive and Underdrive controls in the dashboard. These modes may increase wear or reduce cooling.",
        isOn: extendedRangeConfigurationBinding
      )
      .accessibilityValue(extendedRangeConfigurationAllowed ? "1" : "0")
      .accessibilityIdentifier(AppAccessibilityIdentifier.Settings.extendedRangeAccess)
    } header: {
      Text("Fan Range Limits")
    }
  }

  private var extendedRangeConfigurationBinding: Binding<Bool> {
    Binding(
      get: { extendedRangeConfigurationAllowed },
      set: { allowed in
        ExpandedRangeConfigurationStore.setAllowed(allowed, defaults: Self.suite)
        extendedRangeConfigurationAllowed = allowed
      }
    )
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

  private var responseDisplayText: String {
    "\(Int(FanResponse(value: fanResponseValue).value * 100))%"
  }
}
