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
            Toggle(isOn: enabledBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                    Text(
                        "\(kind.shortTitle) load can raise the curve to a minimum fan floor without changing the main temperature graph."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if enabled {
                LoadAssistCurveEditor(points: $points, minimumPointSpacing: minimumPointSpacing)
                    .frame(height: 168)

                HStack {
                    Text("Load %")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Minimum Fan %")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    let floorPercent = Int((points.last?.fanPercent ?? 0) * 100)
                    let activation = Int(points.dropLast().last?.temperature ?? 0)
                    Text("Starts ramping near \(activation)% load")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Current floor \(floorPercent)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

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
