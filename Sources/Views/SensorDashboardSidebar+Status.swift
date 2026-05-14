//
//  SensorDashboardSidebar+Status.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-10.
//  Copyright © 2026
//

import AppLog
import SwiftUI

private let sensorDashboardSidebarStatusLog = AppLog.make(category: "SensorDashboardSidebar")

extension SensorDashboardSidebar {
    var systemStatus: SystemStatus {
        let helperReachable = runtime.isFresh ? runtime.helperReachable : installState.helperReachable
        if helperReachable, installState.agentEnabled, installState.agentLive, installState.agentSnapshotCompatible {
            return .green
        }
        if helperReachable, installState.agentEnabled, !installState.agentLive {
            return .orange
        }
        if installState.agentEnabled, !helperReachable {
            return .orange
        }
        return .red
    }

    var statusLabel: String {
        if presentation.installationStep == .helperMissing { return "System Helper Required" }
        if presentation.installationStep == .agentMissing { return "Background Control Required" }
        let approvalPending =
            presentation.installationStep == .agentAwaitingApproval
            || presentation.installationStep == .helperAwaitingApproval
        if approvalPending {
            return "Approval Required"
        }
        if presentation.chartState == .degraded {
            return presentation.telemetryFresh ? "Telemetry Unavailable" : "Agent Not Responding"
        }
        if !fanControlReady { return "Fan Control Not Set Up" }
        switch systemStatus {
        case .green: return "All systems go"
        case .orange:
            if installState.agentEnabled, installState.agentLive, !installState.agentSnapshotCompatible {
                return "Update Required"
            }
            if installState.agentEnabled, !installState.agentLive {
                return "Fan Control Paused"
            }
            return "Fan Control Offline"
        case .red: return "Fan Control Unavailable"
        }
    }

    var statusColor: Color {
        if presentation.chartState == .degraded { return Color(nsColor: .systemRed) }
        switch systemStatus {
        case .green: return Color(nsColor: .systemGreen)
        case .orange: return Color(nsColor: .systemOrange)
        case .red: return Color(nsColor: .systemRed)
        }
    }

    var statusBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.6), radius: 3)
                Text(statusLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            if !installState.agentLastError.isEmpty {
                Text("Fan Curve needs attention. Open settings or try setup again.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Fan Curve needs attention. Open settings or try setup again.")
            }
        }
    }

    var activeAssistStates: [ActiveAssistState] {
        guard fanControlReady, presentation.showsRuntimeStats, curveModel.isActive, !boost else { return [] }
        let curveReferenceTemp = runtime.rawPressureTemperature ?? runtime.governingTemperature
        let basePercent = curveModel.evaluate(at: curveReferenceTemp)
        var candidates: [ActiveAssistState] = []
        let floorPercent = runtime.assistFloorPercent ?? 0
        for kind in LoadAssistKind.allCases {
            let enabled = kind == .cpu ? cpuLoadAssistEnabled : gpuLoadAssistEnabled
            guard enabled else { continue }
            let load = kind == .cpu ? runtime.cpuLoadPercent : runtime.gpuLoadPercent
            guard runtime.activeAssistKinds.contains(kind), floorPercent > basePercent + 0.005 else { continue }
            candidates.append(ActiveAssistState(kind: kind, loadPercent: load, floorPercent: floorPercent))
        }
        guard let maxFloor = candidates.map(\.floorPercent).max() else { return [] }
        return candidates.filter { abs($0.floorPercent - maxFloor) < 0.001 }
    }

    func loadAssistCaption(_ assist: ActiveAssistState) -> some View {
        let color = Color(nsColor: .systemTeal)
        let floor = Int((assist.floorPercent * 100).rounded())
        let load = Int(assist.loadPercent.rounded())
        let text = "\(assist.kind.shortTitle) assist holding minimum \(floor)% at \(load)% load"

        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: "arrow.up.forward.circle.fill")
                .font(.system(size: 11))
            Text(text)
                .font(.caption)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .modifier(LoadFloorGlassModifier(color: color, active: true))
        .help(
            "\(assist.kind.title) is active and is currently raising the effective minimum fan floor to \(floor)%."
        )
    }

    func runtimeLoadValue(_ value: Double) -> Double? {
        guard presentation.showsRuntimeStats else { return nil }
        return value
    }

    func usageRow(label: String, icon: String, value: Double?, tint: Color) -> some View {
        let roundedValue = value.map { Int($0.rounded()) }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.callout)
                    .foregroundColor(.secondary)
                Spacer()
                if let roundedValue {
                    Text("\(roundedValue)%")
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(
                            renderMode.allowsLiveAnimation ? .easeOut(duration: 0.32) : nil,
                            value: roundedValue
                        )
                } else {
                    Text("--")
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                    if let value {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tint)
                            .frame(width: geometry.size.width * CGFloat(value / 100))
                            .animation(
                                renderMode.allowsLiveAnimation ? .easeOut(duration: 0.32) : nil,
                                value: value
                            )
                    }
                }
            }
            .frame(height: 4)
        }
    }

    func fanRow(_ fan: AgentFanSnapshot) -> some View {
        let displayedRPM = Int(fan.actualRPM)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    fanIcon(fan: fan)
                    Text("Fan \(fan.id)")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    if fan.manualMode {
                        Text("Manual")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(displayedRPM)")
                        .font(.system(.title3, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(
                            renderMode.allowsLiveAnimation ? .easeOut(duration: 0.38) : nil,
                            value: displayedRPM
                        )
                    Text("RPM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if renderMode.allowsLiveAnimation, isRamping(fan) {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                            .help(
                                "Ramping to \(Int(fan.targetRPM)) RPM. Spinner stops when the fan settles within range."
                            )
                    }
                }
            }
            Spacer()
        }
    }

    func fanIcon(fan: AgentFanSnapshot) -> some View {
        RPMFanIcon(
            rpm: fan.actualRPM,
            minRPM: fan.minRPM,
            maxRPM: fan.maxRPM,
            renderMode: renderMode
        )
    }

    var tempColor: Color {
        guard let temperature = liveTemperatureCelsius else { return .secondary }
        if temperature < 55 { return Color(nsColor: .systemGreen) }
        if temperature < 75 { return Color(nsColor: .systemYellow) }
        if temperature < 90 { return Color(nsColor: .systemOrange) }
        return Color(nsColor: .systemRed)
    }

    var displayedTemperature: Int? {
        guard let temperature = liveTemperatureCelsius else { return nil }
        return Int(unit.convert(fromCelsius: temperature).rounded())
    }

    var liveTemperatureCelsius: Double? {
        guard presentation.showsRuntimeStats else { return nil }
        let temperature = runtime.governingTemperature
        guard temperature > 0 else { return nil }
        return temperature
    }
}
