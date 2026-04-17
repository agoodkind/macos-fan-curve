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
  @ObservedObject var installState: InstallationState

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

      Spacer()

      // Status line stays at the bottom and mirrors the health of the
      // helper daemon plus the background agent.
      systemStatusRow
    }
    .padding(20)
    .frame(width: 240)
  }

  // MARK: - Status

  private enum SystemStatus { case green, orange, red }

  private var systemStatus: SystemStatus {
    switch (installState.helperReachable, installState.agentEnabled) {
    case (true, true): return .green
    case (false, true): return .orange
    default: return .red
    }
  }

  private var statusLabel: String {
    switch systemStatus {
    case .green: return "All systems go"
    case .orange: return "Helper offline"
    case .red: return "Not connected"
    }
  }

  private var statusColor: Color {
    switch systemStatus {
    case .green: return Color(nsColor: .systemGreen)
    case .orange: return Color(nsColor: .systemOrange)
    case .red: return Color(nsColor: .systemRed)
    }
  }

  @ViewBuilder
  private var systemStatusRow: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(statusColor)
        .frame(width: 8, height: 8)
        .shadow(color: statusColor.opacity(0.6), radius: 3)
      Text(statusLabel)
        .font(.caption)
        .foregroundColor(.secondary)
      Spacer()
    }
  }

  // MARK: - Rows

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
