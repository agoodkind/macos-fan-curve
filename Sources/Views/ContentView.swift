//
//  ContentView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import SwiftUI

struct ContentView: View {
  @EnvironmentObject var xpcClient: XPCClient
  @StateObject private var curveModel = FanCurveModel()
  @StateObject private var sensorState = SensorState()
  @StateObject private var installState = InstallationState()
  @State private var controller: FanCurveController?

  var body: some View {
    Group {
      if installState.step == .ready {
        mainLayout
      } else {
        OnboardingView(state: installState)
      }
    }
    .frame(minWidth: 800, idealWidth: 960, minHeight: 480, idealHeight: 560)
    .background(Color(nsColor: .windowBackgroundColor))
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: openSettings) {
          Image(systemName: "gearshape")
        }
        .help("Settings")
      }
    }
    .onAppear {
      installState.startMonitoring(xpcClient: xpcClient)
      let ctrl = FanCurveController(xpcClient: xpcClient, sensorState: sensorState)
      controller = ctrl
      ctrl.start()
    }
    .onDisappear {
      installState.stopMonitoring()
      controller?.stop()
    }
  }

  private var mainLayout: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        FanCurveEditor(model: curveModel, sensorState: sensorState)
          .padding(16)
      }

      Divider().opacity(0.15)

      SensorDashboard(
        sensorState: sensorState,
        curveModel: curveModel,
        installState: installState
      )
    }
  }

  /// Open the built-in Settings scene. Works on macOS 13 through 26 without
  /// requiring the macOS 14 only `@Environment(\.openSettings)` API.
  private func openSettings() {
    if #available(macOS 14.0, *) {
      NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    } else {
      NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
  }
}
