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

private enum LoadAssistModuleConstants {
    static let curveEditorHeight: CGFloat = 168
    static let fanPercentScale = 100.0
    static let contentVStackSpacing: CGFloat = 10
}

struct LoadAssistModuleView: View {
    let kind: LoadAssistKind

    @State private var enabled = false
    @State private var points: [CurvePoint] = []

    private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
    private let minimumPointSpacing = 4.0

    var body: some View {
        VStack(alignment: .leading, spacing: LoadAssistModuleConstants.contentVStackSpacing) {
            SettingsToggleDescriptionRow(
                title: kind.title,
                description: loadAssistDescription,
                isOn: enabledBinding
            )

            if enabled {
                LoadAssistCurveEditor(points: $points, minimumPointSpacing: minimumPointSpacing)
                    .frame(height: LoadAssistModuleConstants.curveEditorHeight)

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
                loadAssistModuleLog.notice(
                    "load_assist.toggle kind=\(kind.rawValue, privacy: .public) enabled=\(newValue, privacy: .public)"
                )
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
        let floorPercent = Int(
            (points.last?.fanPercent ?? 0) * LoadAssistModuleConstants.fanPercentScale)
        return "Current floor \(floorPercent)%"
    }

    private func load() {
        LoadAssistStore.migrateLegacyIfNeeded(defaults: Self.suite)
        enabled = LoadAssistStore.loadEnabled(kind, defaults: Self.suite)
        points = LoadAssistStore.loadPoints(kind, defaults: Self.suite)
        loadAssistModuleLog.debug(
            "load_assist.loaded kind=\(kind.rawValue, privacy: .public) point_count=\(points.count, privacy: .public)"
        )
    }

    private func savePoints() {
        guard !points.isEmpty else { return }
        LoadAssistStore.savePoints(points, kind: kind, defaults: Self.suite)
        loadAssistModuleLog.debug(
            "load_assist.points_saved kind=\(kind.rawValue, privacy: .public) point_count=\(points.count, privacy: .public)"
        )
    }
}
