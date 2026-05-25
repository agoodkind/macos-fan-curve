//
//  SensorDashboardSidebar+Support.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026
//

import AppLog
import SwiftUI

private let sensorDashboardSidebarLog = AppLog.make(category: "SensorDashboardSidebar")

extension SensorDashboardSidebar {
    enum SystemStatus { case green, orange, red }

    enum SidebarPendingAction: Hashable {
        case helperSetup
        case agentSetup
        case openSystemSettings
        case enableBoost
        case disableBoost
        case setFanControl(Bool)

        var logName: String {
            switch self {
            case .helperSetup: return "helper_setup"
            case .agentSetup: return "agent_setup"
            case .openSystemSettings: return "open_system_settings"
            case .enableBoost: return "enable_boost"
            case .disableBoost: return "disable_boost"
            case .setFanControl(let enabled):
                return enabled ? "enable_fan_control" : "disable_fan_control"
            }
        }

        var timeoutNanoseconds: UInt64 {
            switch self {
            case .helperSetup, .agentSetup:
                return 30_000_000_000
            case .openSystemSettings:
                return 8_000_000_000
            case .enableBoost, .disableBoost, .setFanControl:
                return 12_000_000_000
            }
        }

        var minimumVisibleDuration: TimeInterval {
            switch self {
            case .helperSetup:
                return 0.75
            case .agentSetup, .openSystemSettings, .enableBoost, .disableBoost, .setFanControl:
                return 0
            }
        }
    }

    struct ActiveAssistState: Identifiable {
        let kind: LoadAssistKind
        let loadPercent: Double
        let floorPercent: Double

        var id: String { kind.rawValue }
    }

    struct SidebarProminentActionConfiguration {
        let title: String
        let systemImage: String?
        let tint: Color
        let active: Bool
        let isBusy: Bool
    }

    func usageBlock(
        label: String,
        icon: String,
        value: Double?,
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
        if presentation.chartState == .degraded {
            if installState.helperNeedsRepair { return "Helper Needs Repair" }
            if presentation.installationStep == .helperMissing { return "System Helper Required" }
            if presentation.installationStep == .agentMissing {
                return "Background Control Required"
            }
            if presentation.installationStep == .helperAwaitingApproval {
                return "Approval Required"
            }
            if presentation.installationStep == .agentAwaitingApproval {
                return "Approval Required"
            }
            return presentation.telemetryFresh ? "Telemetry Unavailable" : "Agent Not Responding"
        }
        if presentation.controlState == .monitorOnly { return "Monitor only" }
        if !fanControlReady { return "Not Set Up" }
        if boost { return "Boost active" }
        return curveModel.isActive ? "Curve active" : "Off"
    }

    var fanControlStateColor: Color {
        if presentation.chartState == .degraded { return statusColor }
        if !fanControlReady { return .secondary }
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
        let targetAction: SidebarPendingAction = boost ? .disableBoost : .enableBoost
        let configuration = SidebarProminentActionConfiguration(
            title: boostButtonLabel,
            systemImage: "bolt.fill",
            tint: Color(nsColor: .systemOrange),
            active: boost,
            isBusy: isPendingAction(targetAction)
        )
        return sidebarProminentActionButton(configuration) {
            sensorDashboardSidebarLog.notice(
                "sidebar.boost.toggled next_enabled=\((!boost), privacy: .public)"
            )
            beginPendingAction(targetAction)
            let enabled = !boost
            Task {
                do {
                    try await runtime.setBoostEnabled(enabled)
                    await MainActor.run {
                        boost = enabled
                    }
                } catch {
                    sensorDashboardSidebarLog.notice(
                        "sidebar.boost.command_failed enabled=\(enabled, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=keep-current-state"
                    )
                    await MainActor.run {
                        completePendingAction(targetAction, reason: "command-failed")
                    }
                }
            }
        }
        .help(boostHelp)
    }

    private var boostButtonLabel: String {
        if isPendingAction(.enableBoost) { return "Boosting Fans" }
        if isPendingAction(.disableBoost) { return "Stopping Boost" }
        return boost ? "Stop Boost" : "Boost Fans"
    }

    func sidebarProminentActionButton(
        _ configuration: SidebarProminentActionConfiguration,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            styledSidebarProminentActionButton(
                configuration,
                action: action
            )
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(!configuration.isBusy)
    }

    @ViewBuilder
    private func styledSidebarProminentActionButton(
        _ configuration: SidebarProminentActionConfiguration,
        action: @escaping () -> Void
    ) -> some View {
        sidebarProminentActionButtonBody(
            configuration,
            action: action
        )
        .buttonStyle(.plain)
        .background {
            Capsule()
                .fill(
                    configuration.active
                        ? configuration.tint
                        : configuration.tint.opacity(0.12)
                )
        }
        .overlay(
            Capsule()
                .stroke(
                    configuration.tint.opacity(configuration.active ? 0 : 0.45),
                    lineWidth: 0.8
                )
        )
    }

    private func sidebarProminentActionButtonBody(
        _ configuration: SidebarProminentActionConfiguration,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !configuration.isBusy else { return }
            action()
        } label: {
            sidebarProminentActionButtonLabel(
                configuration
            )
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func sidebarProminentActionButtonLabel(
        _ configuration: SidebarProminentActionConfiguration
    ) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            if configuration.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(configuration.active ? Color.white : configuration.tint)
            } else if let systemImage = configuration.systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(
                        configuration.active ? Color.white : configuration.tint
                    )
            }

            Text(configuration.title)
                .foregroundStyle(configuration.active ? Color.white : Color.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .font(.callout.weight(.medium))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    var boostHelp: String {
        "Pins all fans to 100% (or Overdrive target) while enabled."
    }
}
