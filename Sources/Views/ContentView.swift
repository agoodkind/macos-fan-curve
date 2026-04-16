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
  @State private var controller: FanCurveController?

  var body: some View {
    HStack(spacing: 0) {
      // Curve editor (main area)
      VStack(spacing: 0) {
        if case .error(let msg) = xpcClient.state {
          HStack {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundColor(.orange)
            Text(msg)
              .font(.caption)
            Spacer()
          }
          .padding(8)
          .background(.orange.opacity(0.1))
        }

        FanCurveEditor(model: curveModel, sensorState: sensorState)
          .padding(16)
      }

      Divider()

      // Sidebar
      if let controller {
        SensorDashboard(
          sensorState: sensorState,
          curveModel: curveModel,
          controller: controller
        )
      }
    }
    .frame(minWidth: 700, minHeight: 400)
    .onAppear {
      let ctrl = FanCurveController(
        xpcClient: xpcClient, curveModel: curveModel, sensorState: sensorState)
      controller = ctrl
      // Start polling for sensor data (display only, not controlling fans)
      ctrl.start()
      // Don't activate curve control by default
      curveModel.isActive = false
    }
    .onDisappear {
      controller?.stop()
    }
  }
}
