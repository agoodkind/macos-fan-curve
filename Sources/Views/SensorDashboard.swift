//
//  SensorDashboard.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import SwiftUI

struct SensorDashboard: View {
  @ObservedObject var sensorState: SensorState
  @ObservedObject var curveModel: FanCurveModel
  @ObservedObject var controller: FanCurveController

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Governing temp
      VStack(alignment: .leading, spacing: 4) {
        Text("CPU Temperature")
          .font(.caption)
          .foregroundColor(.secondary)
        Text("\(Int(sensorState.governingTemperature))C")
          .font(.system(size: 36, weight: .light, design: .rounded))
          .foregroundColor(tempColor)
      }

      Divider()

      // Fans
      ForEach(sensorState.fans) { fan in
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Fan \(fan.id)")
              .font(.caption)
              .foregroundColor(.secondary)
            Text("\(Int(fan.actualRPM)) RPM")
              .font(.system(.body, design: .monospaced))
          }
          Spacer()
          Text(fan.manualMode ? "Manual" : "Auto")
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(fan.manualMode ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
            .clipShape(Capsule())
        }
      }

      Divider()

      // Controls
      Toggle("Active", isOn: $curveModel.isActive)
        .onChange(of: curveModel.isActive) { active in
          if active { controller.start() }
          else { controller.stop() }
        }

      Picker("Interpolation", selection: $curveModel.interpolationMode) {
        Text("Linear").tag(InterpolationMode.linear)
        Text("Smooth").tag(InterpolationMode.catmullRom)
      }
      .pickerStyle(.segmented)
      .onChange(of: curveModel.interpolationMode) { _ in
        curveModel.save()
      }

      Button("Reset to Default") {
        curveModel.resetToDefault()
      }
      .buttonStyle(.plain)
      .foregroundColor(.red)
      .font(.caption)

      Spacer()

      // Connection + update
      if let lastUpdate = sensorState.lastUpdate {
        Text("Updated \(lastUpdate, style: .relative) ago")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
    .padding()
    .frame(width: 200)
  }

  private var tempColor: Color {
    let t = sensorState.governingTemperature
    if t < 50 { return .green }
    if t < 70 { return .yellow }
    if t < 85 { return .orange }
    return .red
  }
}
