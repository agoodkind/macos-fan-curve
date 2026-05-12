//
//  LoadAssistModuleView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026
//

import AppLog
import SwiftUI

private let loadAssistModuleLog = AppLog.make(category: "LoadAssistModule")

struct LoadAssistModuleView: View {
    let kind: LoadAssistKind

    @State private var enabled = false
    @State private var points: [CurvePoint] = []

    private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
    private let minimumPointSpacing = 4.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsToggleDescriptionRow(
                title: kind.title,
                description: loadAssistDescription,
                isOn: enabledBinding
            )

            if enabled {
                LoadAssistCurveEditor(points: $points, minimumPointSpacing: minimumPointSpacing)
                    .frame(height: 168)

                SettingsKeyValueRow(label: "Load %", value: "Minimum Fan %")

                SettingsKeyValueRow(label: activationSummary, value: floorSummary)

                Button("Reset \(kind.shortTitle) Assist Curve") {
                    points = LoadAssistStore.defaultPoints()
                }
                .controlSize(.small)
            }
        }
        .onAppear(perform: load)
        .onChange(of: points) { _ in savePoints() }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { enabled },
            set: { newValue in
                enabled = newValue
                LoadAssistStore.saveEnabled(newValue, kind: kind, defaults: Self.suite)
            })
    }

    private var loadAssistDescription: String {
        "\(kind.shortTitle) load can raise the curve to a minimum fan floor without changing the main temperature graph."
    }

    private var activationSummary: String {
        let activation = Int(points.dropLast().last?.temperature ?? 0)
        return "Starts ramping near \(activation)% load"
    }

    private var floorSummary: String {
        let floorPercent = Int((points.last?.fanPercent ?? 0) * 100)
        return "Current floor \(floorPercent)%"
    }

    private func load() {
        LoadAssistStore.migrateLegacyIfNeeded(defaults: Self.suite)
        enabled = LoadAssistStore.loadEnabled(kind, defaults: Self.suite)
        points = LoadAssistStore.loadPoints(kind, defaults: Self.suite)
    }

    private func savePoints() {
        guard !points.isEmpty else { return }
        LoadAssistStore.savePoints(points, kind: kind, defaults: Self.suite)
    }
}
