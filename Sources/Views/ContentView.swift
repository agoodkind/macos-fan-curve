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
      // Curve editor
      VStack(spacing: 0) {
        if case .error(let msg) = xpcClient.state {
          HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundColor(.orange)
              .font(.system(size: 11))
            Text(msg)
              .font(.system(size: 11))
              .lineLimit(1)
            Spacer()
            Button("Reconnect") { xpcClient.connect() }
              .font(.system(size: 10))
              .buttonStyle(.plain)
              .foregroundColor(.accentColor)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(.orange.opacity(0.08))
        }

        FanCurveEditor(model: curveModel, sensorState: sensorState)
          .padding(12)
      }

      Divider().opacity(0.3)

      if let controller {
        SensorDashboard(
          sensorState: sensorState,
          curveModel: curveModel,
          controller: controller
        )
      }
    }
    .frame(minWidth: 750, idealWidth: 900, minHeight: 420, idealHeight: 500)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear {
      let ctrl = FanCurveController(
        xpcClient: xpcClient, curveModel: curveModel, sensorState: sensorState)
      controller = ctrl
      ctrl.start()
      curveModel.isActive = false
    }
    .onDisappear {
      controller?.stop()
    }
  }
}
