//
//  SensorDashboardSidebar+Support.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026
//

import SwiftUI

extension SensorDashboardSidebar {
    enum SystemStatus { case green, orange, red }

    struct ActiveAssistState: Identifiable {
        let kind: LoadAssistKind
        let loadPercent: Double
        let floorPercent: Double

        var id: String { kind.rawValue }
    }

    func usageBlock(
        label: String,
        icon: String,
        value: Double,
        tint: Color,
        assist: ActiveAssistState?
    ) -> some View {
        VStack(spacing: 4) {
            usageRow(
                label: label,
                icon: icon,
                value: value,
                tint: tint
            )
            if let assist {
                loadAssistCaption(assist)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        )
                    )
            }
        }
    }

    var fanControlStateLabel: String {
        if boost { return "Boost active" }
        return curveModel.isActive ? "Curve active" : "Off"
    }

    var fanControlStateColor: Color {
        if boost { return Color(nsColor: .systemOrange) }
        return curveModel.isActive ? Color.accentColor : .secondary
    }

    var controllerStateLabel: String {
        let targetPercent = clampedPercent(runtime.commandedTargetPercent)
        let target = Int((targetPercent * 100).rounded())

        guard let observedPercent else {
            return "Targeting \(target)%"
        }

        let delta = targetPercent - observedPercent
        if delta > 0.02 {
            return "Stepping up toward \(target)%"
        }
        if delta < -0.02 {
            return "Cooling down toward \(target)%"
        }
        return "Targeting \(target)%"
    }

    var observedPercent: Double? {
        let percents = runtime.fans.compactMap { fan -> Double? in
            guard let range = effectiveRPMRange(for: fan), fan.actualRPM > 0 else { return nil }
            return clampedPercent(Double((fan.actualRPM - range.min) / (range.max - range.min)))
        }
        guard !percents.isEmpty else { return nil }
        return percents.reduce(0, +) / Double(percents.count)
    }

    func effectiveRPMRange(for fan: AgentFanSnapshot) -> (min: Float, max: Float)? {
        let minRPM: Float = underdriveEnabled ? 0 : fan.minRPM
        let maxRPM: Float = overdriveEnabled ? max(fan.maxRPM, overdriveTargetRPM) : fan.maxRPM
        guard maxRPM > minRPM else { return nil }
        return (minRPM, maxRPM)
    }

    func clampedPercent(_ percent: Double) -> Double {
        max(0, min(1, percent))
    }

    func isRamping(_ fan: AgentFanSnapshot) -> Bool {
        let target = fan.targetRPM
        guard target > 0 else { return false }
        if fan.actualRPM >= fan.maxRPM - 50 { return false }
        let tolerance = max(250, target * 0.05)
        return abs(fan.actualRPM - target) > tolerance
    }

    var boostButton: some View {
        let label = Label(
            boost ? "Stop Boost" : "Boost Fans",
            systemImage: "bolt.fill"
        )
        return Group {
            if #available(macOS 26.0, *) {
                modernBoostButton(label: label)
            } else if boost {
                Button {
                    boost.toggle()
                } label: {
                    label.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(nsColor: .systemOrange))
                .controlSize(.regular)
                .help(boostHelp)
            } else {
                Button {
                    boost.toggle()
                } label: {
                    label.frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help(boostHelp)
            }
        }
    }

    @available(macOS 26.0, *)
    private func modernBoostButton(label _: Label<Text, Image>) -> some View {
        let orange = Color(nsColor: .systemOrange)
        return Button {
            boost.toggle()
        } label: {
            ZStack {
                Text(boost ? "Stop Boost" : "Boost Fans")
                    .foregroundStyle(boost ? Color.white : Color.primary)
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(boost ? Color.white : orange)
                    Spacer()
                }
                .padding(.leading, 14)
            }
            .font(.callout.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .background {
            Capsule()
                .fill(boost ? orange : orange.opacity(0.12))
        }
        .overlay(
            Capsule()
                .stroke(orange.opacity(boost ? 0 : 0.45), lineWidth: 0.8)
        )
        .help(boostHelp)
    }

    var boostHelp: String {
        "Pins all fans to 100% (or Overdrive target) while enabled."
    }

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
        switch systemStatus {
        case .green: return "All systems go"
        case .orange:
            if installState.agentEnabled, installState.agentLive, !installState.agentSnapshotCompatible {
                return "Agent update pending"
            }
            if installState.agentEnabled, !installState.agentLive {
                return "Agent not responding"
            }
            return "Helper offline"
        case .red: return "Not connected"
        }
    }

    var statusColor: Color {
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
                Text(installState.agentLastError)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(installState.agentLastError)
            }
        }
    }

    var activeAssistStates: [ActiveAssistState] {
        guard curveModel.isActive, !boost else { return [] }
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

    func usageRow(label: String, icon: String, value: Double, tint: Color) -> some View {
        let roundedValue = Int(value.rounded())
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.callout)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(roundedValue)%")
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.32), value: roundedValue)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(width: geometry.size.width * CGFloat(value / 100))
                        .animation(.easeOut(duration: 0.32), value: value)
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
                        .animation(.easeOut(duration: 0.38), value: displayedRPM)
                    Text("RPM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if isRamping(fan) {
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
        let temperature = runtime.governingTemperature
        if temperature < 55 { return Color(nsColor: .systemGreen) }
        if temperature < 75 { return Color(nsColor: .systemYellow) }
        if temperature < 90 { return Color(nsColor: .systemOrange) }
        return Color(nsColor: .systemRed)
    }
}
