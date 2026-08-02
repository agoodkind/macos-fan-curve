//
//  SensorDashboard.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import SwiftUI

private let sensorDashboardLog = AppLog.make(category: "SensorDashboard")

struct SensorDashboard: View {
  @ObservedObject var runtime: FanCurveAgentClient
  @ObservedObject var curveModel: FanCurveModel
  @ObservedObject var installState: InstallationState
  let renderMode: AppRenderMode
  let presentation: DashboardPresentationState

  @AppStorage("temperatureUnit") private var unitRaw: String = "celsius"

  private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

  @AppStorage(SharedConfigKeys.boostEnabled, store: suite)
  private var boost: Bool = false

  @AppStorage(SharedConfigKeys.cpuLoadAssistEnabled, store: suite)
  private var cpuLoadAssistEnabled: Bool = false

  @AppStorage(SharedConfigKeys.gpuLoadAssistEnabled, store: suite)
  private var gpuLoadAssistEnabled: Bool = false

  private var unit: TemperatureUnit {
    TemperatureUnit(rawValue: unitRaw) ?? .celsius
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        SensorDashboardSidebar(
          runtime: runtime,
          curveModel: curveModel,
          installState: installState,
          renderMode: renderMode,
          unit: unit,
          boost: $boost,
          cpuLoadAssistEnabled: cpuLoadAssistEnabled,
          gpuLoadAssistEnabled: gpuLoadAssistEnabled,
          presentation: presentation
        )
        .frame(minHeight: geometry.size.height)
      }
      .scrollIndicators(.hidden)
    }
    .fancurveGlass(
      in: RoundedRectangle(cornerRadius: 0),
      fallbackFill: Color(nsColor: .windowBackgroundColor)
    )
    .accessibilityIdentifier(AppAccessibilityIdentifier.Dashboard.sidebar)
    .onAppear {
      LoadAssistStore.migrateLegacyIfNeeded(defaults: Self.suite)
      sensorDashboardLog.info(
        "sensor_dashboard.appeared render_mode=\(String(describing: renderMode), privacy: .public) fps=\(renderMode.preferredFramesPerSecond, privacy: .public)"
      )
    }
  }
}
