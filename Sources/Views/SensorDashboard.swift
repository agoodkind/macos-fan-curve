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
      // Hero temp
      VStack(alignment: .leading, spacing: 2) {
        Text("CPU")
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .foregroundColor(.secondary)
        HStack(alignment: .firstTextBaseline, spacing: 1) {
          Text("\(Int(sensorState.governingTemperature))")
            .font(.system(size: 42, weight: .ultraLight, design: .rounded))
            .foregroundColor(tempColor)
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.6), value: Int(sensorState.governingTemperature))
          Text("°C")
            .font(.system(size: 16, weight: .ultraLight))
            .foregroundColor(tempColor.opacity(0.6))
        }
      }

      // Fans
      VStack(spacing: 10) {
        ForEach(sensorState.fans) { fan in
          HStack {
            VStack(alignment: .leading, spacing: 1) {
              Text("Fan \(fan.id)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
              HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(fan.actualRPM))")
                  .font(.system(size: 20, weight: .light, design: .rounded))
                  .contentTransition(.numericText())
                  .animation(.easeInOut(duration: 0.6), value: Int(fan.actualRPM))
                Text("RPM")
                  .font(.system(size: 9))
                  .foregroundColor(.secondary)
              }
            }
            Spacer()
            Text(fan.manualMode ? "Manual" : "Auto")
              .font(.system(size: 9, weight: .medium))
              .padding(.horizontal, 6)
              .padding(.vertical, 3)
              .background(
                (fan.manualMode ? Color.orange : Color.green).opacity(0.1)
              )
              .foregroundColor(fan.manualMode ? .orange : .green)
              .clipShape(Capsule())
          }
        }
      }

      Divider().opacity(0.2)

      // Controls
      VStack(alignment: .leading, spacing: 14) {
        Toggle(isOn: $curveModel.isActive) {
          Text("Apply Curve")
            .font(.system(size: 12))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(Color(nsColor: .systemCyan))
        .onChange(of: curveModel.isActive) { active in
          if active { controller.start() }
          else { controller.stop() }
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("Mode")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
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

      // Footer
      HStack(spacing: 6) {
        Button(action: { curveModel.resetToDefault() }) {
          Label("Reset", systemImage: "arrow.counterclockwise")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)

        Spacer()

        Circle()
          .fill(sensorState.lastUpdate != nil ? Color.green : Color.gray)
          .frame(width: 5, height: 5)
      }
    }
    .padding(16)
    .frame(width: 200)
  }

  private var tempColor: Color {
    let t = sensorState.governingTemperature
    if t < 55 { return Color(nsColor: .systemGreen) }
    if t < 75 { return Color(nsColor: .systemYellow) }
    if t < 90 { return Color(nsColor: .systemOrange) }
    return Color(nsColor: .systemRed)
  }
}
