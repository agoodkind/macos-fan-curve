//
//  SensorDashboardSidebar+Status.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-10.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import SwiftUI

// MARK: - Layout and threshold constants

private enum SidebarStatusConstants {
    // Status indicator dot
    static let statusDotSize: CGFloat = 8
    static let statusDotShadowOpacity: Double = 0.6
    static let statusDotShadowRadius: CGFloat = 3

    // Status block layout
    static let statusBlockSpacing: CGFloat = 8
    static let statusHStackSpacing: CGFloat = 8
    static let statusDetailLineLimit = 3

    // Assist floor thresholds (fractional, range 0 to 1)
    static let assistFloorActivationMargin: Double = 0.005
    static let assistFloorFilterTolerance: Double = 0.001

    // Assist caption row
    static let assistCaptionHStackSpacing: CGFloat = 6
    static let assistCaptionIconSize: CGFloat = 11
    static let assistCaptionHorizontalPadding: CGFloat = 10
    static let assistCaptionVerticalPadding: CGFloat = 5
    static let assistCaptionLineLimit = 2

    // Percent scale factor (fractional to whole number)
    static let percentScale: Double = 100

    // Usage row layout
    static let usageRowVStackSpacing: CGFloat = 4
    static let usageRowBarCornerRadius: CGFloat = 2
    static let usageRowBarTrackOpacity: Double = 0.15
    static let usageRowBarHeight: CGFloat = 4
    static let usageRowAnimationDuration: Double = 0.32

    // Fan row layout
    static let fanRowInnerVStackSpacing: CGFloat = 2
    static let fanRowTopHStackSpacing: CGFloat = 4
    static let fanRowRPMHStackSpacing: CGFloat = 3
    static let fanRowRPMAnimationDuration: Double = 0.38
    static let fanRowRampingSpinnerScale: CGFloat = 0.7

    // Temperature color thresholds in degrees Celsius
    static let tempGreenMaxCelsius: Double = 55
    static let tempYellowMaxCelsius: Double = 75
    static let tempOrangeMaxCelsius: Double = 90
}

private let sensorDashboardSidebarStatusLog = AppLog.make(category: "SensorDashboardSidebar")

extension SensorDashboardSidebar {
    var systemStatus: SystemStatus {
        let helperReachable =
            runtime.isFresh ? runtime.helperReachable : installState.helperReachable
        let setupNeedsAttention =
            installState.step == .helperAwaitingApproval
            || installState.step == .agentAwaitingApproval
            || installState.step == .agentMissing
        if setupNeedsAttention {
            return .orange
        }
        if installState.step == .helperMissing {
            // A reachable helper with a stale registration record is a non-blocking
            // repair rather than an outage, so it must not read as hard red while live
            // telemetry is flowing. Only an unreachable helper is a true red failure.
            return helperReachable ? .orange : .red
        }
        if presentation.chartState == .degraded {
            return .red
        }
        let isFullyOperational =
            helperReachable
            && installState.agentEnabled
            && installState.agentLive
            && installState.agentSnapshotCompatible
        if isFullyOperational {
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
        let helperReachable =
            runtime.isFresh ? runtime.helperReachable : installState.helperReachable
        if installState.step == .helperMissing {
            return helperReachable ? "System Helper Needs Repair" : "System Helper Required"
        }
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
            let needsUpdate =
                installState.agentEnabled
                && installState.agentLive
                && !installState.agentSnapshotCompatible
            if needsUpdate {
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
        switch systemStatus {
        case .green: return Color(nsColor: .systemGreen)
        case .orange: return Color(nsColor: .systemOrange)
        case .red: return Color(nsColor: .systemRed)
        }
    }

    var statusBlock: some View {
        VStack(alignment: .leading, spacing: SidebarStatusConstants.statusBlockSpacing) {
            HStack(spacing: SidebarStatusConstants.statusHStackSpacing) {
                Circle()
                    .fill(statusColor)
                    .frame(
                        width: SidebarStatusConstants.statusDotSize,
                        height: SidebarStatusConstants.statusDotSize
                    )
                    .shadow(
                        color: statusColor.opacity(SidebarStatusConstants.statusDotShadowOpacity),
                        radius: SidebarStatusConstants.statusDotShadowRadius
                    )
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
                    .lineLimit(SidebarStatusConstants.statusDetailLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Fan Curve needs attention. Open settings or try setup again.")
            }
        }
        .onAppear {
            sensorDashboardSidebarStatusLog.debug(
                "sidebar.status.appeared label=\(statusLabel, privacy: .public)"
            )
        }
    }

    var activeAssistStates: [ActiveAssistState] {
        guard fanControlReady, presentation.showsRuntimeStats, curveModel.isActive, !boost else {
            return []
        }
        let curveReferenceTemp = runtime.rawPressureTemperature ?? runtime.governingTemperature
        let basePercent = curveModel.evaluate(at: curveReferenceTemp)
        var candidates: [ActiveAssistState] = []
        let floorPercent = runtime.assistFloorPercent ?? 0
        for kind in LoadAssistKind.allCases {
            let enabled = kind == .cpu ? cpuLoadAssistEnabled : gpuLoadAssistEnabled
            guard enabled else { continue }
            let load = kind == .cpu ? runtime.cpuLoadPercent : runtime.gpuLoadPercent
            guard runtime.activeAssistKinds.contains(kind),
                floorPercent > basePercent + SidebarStatusConstants.assistFloorActivationMargin
            else { continue }
            candidates.append(
                ActiveAssistState(kind: kind, loadPercent: load, floorPercent: floorPercent))
        }
        guard let maxFloor = candidates.map(\.floorPercent).max() else { return [] }
        return candidates.filter { candidate in
            let tolerance = SidebarStatusConstants.assistFloorFilterTolerance
            return abs(candidate.floorPercent - maxFloor) < tolerance
        }
    }

    func loadAssistCaption(_ assist: ActiveAssistState) -> some View {
        let color = Color(nsColor: .systemTeal)
        let floor = Int((assist.floorPercent * SidebarStatusConstants.percentScale).rounded())
        let load = Int(assist.loadPercent.rounded())
        let text = "\(assist.kind.shortTitle) assist holding minimum \(floor)% at \(load)% load"

        return HStack(alignment: .top, spacing: SidebarStatusConstants.assistCaptionHStackSpacing) {
            Image(systemName: "arrow.up.forward.circle.fill")
                .font(.system(size: SidebarStatusConstants.assistCaptionIconSize))
            Text(text)
                .font(.caption)
                .lineLimit(SidebarStatusConstants.assistCaptionLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(color)
        .padding(.horizontal, SidebarStatusConstants.assistCaptionHorizontalPadding)
        .padding(.vertical, SidebarStatusConstants.assistCaptionVerticalPadding)
        .modifier(LoadFloorGlassModifier(color: color, active: true))
        .help(
            "\(assist.kind.title) is active and is currently raising the effective minimum fan floor to \(floor)%."
        )
    }

    func runtimeLoadValue(_ value: Double) -> Double? {
        guard presentation.showsRuntimeStats else { return nil }
        return value
    }

    private var usageRowAnimation: Animation? {
        guard renderMode.allowsLiveAnimation else { return nil }
        return .easeOut(duration: SidebarStatusConstants.usageRowAnimationDuration)
    }

    func usageRow(label: String, icon: String, value: Double?, tint: Color) -> some View {
        let roundedValue = value.map { rawValue in Int(rawValue.rounded()) }
        return VStack(alignment: .leading, spacing: SidebarStatusConstants.usageRowVStackSpacing) {
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
                        .animation(usageRowAnimation, value: roundedValue)
                } else {
                    Text("--")
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: SidebarStatusConstants.usageRowBarCornerRadius)
                        .fill(
                            Color.secondary.opacity(SidebarStatusConstants.usageRowBarTrackOpacity))
                    if let value {
                        RoundedRectangle(
                            cornerRadius: SidebarStatusConstants.usageRowBarCornerRadius
                        )
                        .fill(tint)
                        .frame(
                            width: geometry.size.width
                                * CGFloat(value / SidebarStatusConstants.percentScale)
                        )
                        .animation(usageRowAnimation, value: value)
                    }
                }
            }
            .frame(height: SidebarStatusConstants.usageRowBarHeight)
        }
    }

    func fanRow(_ fan: AgentFanSnapshot) -> some View {
        let displayedRPM = Int(fan.actualRPM)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: SidebarStatusConstants.fanRowInnerVStackSpacing) {
                HStack(spacing: SidebarStatusConstants.fanRowTopHStackSpacing) {
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
                HStack(
                    alignment: .firstTextBaseline,
                    spacing: SidebarStatusConstants.fanRowRPMHStackSpacing
                ) {
                    Text("\(displayedRPM)")
                        .font(.system(.title3, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(
                            renderMode.allowsLiveAnimation
                                ? .easeOut(
                                    duration: SidebarStatusConstants.fanRowRPMAnimationDuration)
                                : nil,
                            value: displayedRPM
                        )
                    Text("RPM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if renderMode.allowsLiveAnimation, isRamping(fan) {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(SidebarStatusConstants.fanRowRampingSpinnerScale)
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
        if temperature < SidebarStatusConstants.tempGreenMaxCelsius {
            return Color(nsColor: .systemGreen)
        }
        if temperature < SidebarStatusConstants.tempYellowMaxCelsius {
            return Color(nsColor: .systemYellow)
        }
        if temperature < SidebarStatusConstants.tempOrangeMaxCelsius {
            return Color(nsColor: .systemOrange)
        }
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
