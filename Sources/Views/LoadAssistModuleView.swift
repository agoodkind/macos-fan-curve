//
//  LoadAssistModuleView.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import SwiftUI

private let loadAssistModuleLog = AppLog.make(category: "LoadAssistModule")

private enum LoadAssistModuleConstants {
  static let curveEditorHeight: CGFloat = 168
  static let contentVStackSpacing: CGFloat = 10
}

struct LoadAssistModuleView: View {
  let kind: LoadAssistKind

  @State private var enabled = false
  @State private var points: [CurvePoint] = []

  private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

  var body: some View {
    VStack(alignment: .leading, spacing: LoadAssistModuleConstants.contentVStackSpacing) {
      SettingsToggleDescriptionRow(
        title: kind.title,
        description: loadAssistDescription,
        isOn: enabledBinding
      )

      if enabled {
        LoadAssistCurveEditor(points: $points)
          .frame(height: LoadAssistModuleConstants.curveEditorHeight)

        Text(chartExplanation)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

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
    switch kind {
    case .cpu:
      return "Keep the fan from dropping too low during CPU-heavy work."
    case .gpu:
      return "Keep the fan from dropping too low during graphics-heavy work."
    }
  }

  private var chartExplanation: String {
    "As \(kind.shortTitle) usage climbs, Fan Curve keeps the fan above the shaded line."
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
