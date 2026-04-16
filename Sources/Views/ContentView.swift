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
          errorBanner(msg)
        }

        FanCurveEditor(model: curveModel, sensorState: sensorState)
          .padding(16)
      }

      Divider().opacity(0.15)

      if let controller {
        SensorDashboard(
          sensorState: sensorState,
          curveModel: curveModel,
          controller: controller
        )
      }
    }
    .frame(minWidth: 800, idealWidth: 960, minHeight: 480, idealHeight: 560)
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

  private func errorBanner(_ msg: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundColor(.orange)
        .font(.body)
      Text(msg)
        .font(.callout)
        .lineLimit(1)
      Spacer()
      Button("Reconnect") { xpcClient.connect() }
        .font(.callout)
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.orange.opacity(0.06))
  }
}
