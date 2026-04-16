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
    VStack(alignment: .leading, spacing: 24) {
      // Hero temp
      VStack(alignment: .leading, spacing: 4) {
        Label("CPU Temperature", systemImage: "thermometer.medium")
          .font(.subheadline)
          .foregroundColor(.secondary)

        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text("\(Int(sensorState.governingTemperature))")
            .font(.system(size: 48, weight: .thin, design: .rounded))
            .foregroundColor(tempColor)
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.6), value: Int(sensorState.governingTemperature))
          Text("°C")
            .font(.system(size: 18, weight: .ultraLight))
            .foregroundColor(tempColor.opacity(0.5))
        }
      }

      // Fans
      VStack(spacing: 14) {
        ForEach(sensorState.fans) { fan in
          fanRow(fan)
        }
      }

      Divider().opacity(0.15)

      // Controls
      VStack(alignment: .leading, spacing: 16) {
        Toggle(isOn: $curveModel.isActive) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Fan Control")
              .font(.body)
            Text(curveModel.isActive ? "Curve active" : "Off")
              .font(.caption)
              .foregroundColor(curveModel.isActive ? Color(nsColor: .systemCyan) : .secondary)
          }
        }
        .toggleStyle(.switch)
        .controlSize(.regular)
        .tint(Color(nsColor: .systemCyan))
        .onChange(of: curveModel.isActive) { active in
          if active { controller.start() }
          else { controller.stop() }
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Interpolation")
            .font(.subheadline)
            .foregroundColor(.secondary)
          Picker("", selection: $curveModel.interpolationMode) {
            Text("Linear").tag(InterpolationMode.linear)
            Text("Smooth").tag(InterpolationMode.catmullRom)
          }
          .pickerStyle(.segmented)
          .onChange(of: curveModel.interpolationMode) { _ in
            curveModel.save()
          }
        }
      }

      Spacer()

      // Footer
      Button(action: { curveModel.resetToDefault() }) {
        Label("Reset Curve", systemImage: "arrow.counterclockwise")
          .font(.callout)
          .foregroundColor(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(20)
    .frame(width: 240)
  }

  private func fanRow(_ fan: FanReading) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          fanIcon(spinning: fan.actualRPM > 0)
          Text("Fan \(fan.id)")
            .font(.callout)
            .foregroundColor(.secondary)
        }
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text("\(Int(fan.actualRPM))")
            .font(.system(.title3, design: .rounded))
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.6), value: Int(fan.actualRPM))
          Text("RPM")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      Spacer()
      statusBadge(manual: fan.manualMode)
    }
  }

  @ViewBuilder
  private func statusBadge(manual: Bool) -> some View {
    let label = manual ? "Manual" : "Auto"
    let color: Color = manual ? .orange : .green

    Text(label)
      .font(.system(.caption2, weight: .medium))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .foregroundColor(color)
      .background(color.opacity(0.1))
      .clipShape(Capsule())
  }

  @ViewBuilder
  private func fanIcon(spinning: Bool) -> some View {
    let icon = Image(systemName: "fan.fill")
      .font(.caption)
      .foregroundColor(spinning ? Color(nsColor: .systemCyan) : .secondary)
    if #available(macOS 15.0, *) {
      icon.symbolEffect(.rotate, isActive: spinning)
    } else {
      icon
    }
  }

  private var tempColor: Color {
    let t = sensorState.governingTemperature
    if t < 55 { return Color(nsColor: .systemGreen) }
    if t < 75 { return Color(nsColor: .systemYellow) }
    if t < 90 { return Color(nsColor: .systemOrange) }
    return Color(nsColor: .systemRed)
  }
}
