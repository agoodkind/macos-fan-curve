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
    VStack(alignment: .leading, spacing: 20) {
      // Governing temp - hero display
      VStack(alignment: .leading, spacing: 2) {
        Text("CPU TEMPERATURE")
          .font(.system(size: 9, weight: .semibold, design: .rounded))
          .foregroundColor(.secondary)
          .tracking(1.5)

        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text("\(Int(sensorState.governingTemperature))")
            .font(.system(size: 48, weight: .ultraLight, design: .rounded))
            .foregroundColor(tempColor)
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.8), value: Int(sensorState.governingTemperature))
          Text("C")
            .font(.system(size: 20, weight: .light, design: .rounded))
            .foregroundColor(tempColor.opacity(0.7))
        }
      }

      // Fans
      VStack(spacing: 12) {
        ForEach(sensorState.fans) { fan in
          HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
              Text("FAN \(fan.id)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .tracking(1)
              HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(fan.actualRPM))")
                  .font(.system(size: 22, weight: .light, design: .rounded))
                  .contentTransition(.numericText())
                  .animation(.easeInOut(duration: 0.8), value: Int(fan.actualRPM))
                Text("RPM")
                  .font(.system(size: 10, weight: .medium, design: .rounded))
                  .foregroundColor(.secondary)
              }
            }
            Spacer()
            Text(fan.manualMode ? "MANUAL" : "AUTO")
              .font(.system(size: 8, weight: .bold, design: .rounded))
              .tracking(0.8)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(
                (fan.manualMode ? Color.orange : Color.green).opacity(0.15)
              )
              .foregroundColor(fan.manualMode ? .orange : .green)
              .clipShape(Capsule())
          }
        }
      }

      Divider().opacity(0.3)

      // Controls
      VStack(alignment: .leading, spacing: 12) {
        Toggle(isOn: $curveModel.isActive) {
          VStack(alignment: .leading, spacing: 1) {
            Text("Curve Control")
              .font(.system(size: 12, weight: .medium))
            Text(curveModel.isActive ? "Applying curve" : "Monitoring only")
              .font(.system(size: 10))
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)
        .tint(.accentColor)
        .onChange(of: curveModel.isActive) { active in
          if active { controller.start() }
          else { controller.stop() }
        }

        VStack(alignment: .leading, spacing: 4) {
          Text("INTERPOLATION")
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundColor(.secondary)
            .tracking(1)
          Picker("", selection: $curveModel.interpolationMode) {
            Text("Linear").tag(InterpolationMode.linear)
            Text("Smooth").tag(InterpolationMode.catmullRom)
          }
          .pickerStyle(.segmented)
          .controlSize(.small)
          .onChange(of: curveModel.interpolationMode) { _ in
            curveModel.save()
          }
        }
      }

      Spacer()

      // Reset + status
      VStack(alignment: .leading, spacing: 8) {
        Button(action: { curveModel.resetToDefault() }) {
          HStack(spacing: 4) {
            Image(systemName: "arrow.counterclockwise")
            Text("Reset Curve")
          }
          .font(.system(size: 11))
          .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)

        if let lastUpdate = sensorState.lastUpdate {
          HStack(spacing: 4) {
            Circle()
              .fill(.green)
              .frame(width: 5, height: 5)
            Text("Live")
              .font(.system(size: 9, weight: .medium, design: .rounded))
              .foregroundColor(.secondary)
          }
        }
      }
    }
    .padding(20)
    .frame(width: 220)
  }

  private var tempColor: Color {
    let t = sensorState.governingTemperature
    if t < 50 { return .green }
    if t < 70 { return .yellow }
    if t < 85 { return .orange }
    return .red
  }
}
