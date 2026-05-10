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
            case .setFanControl(let enabled): return enabled ? "enable_fan_control" : "disable_fan_control"
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
            if presentation.installationStep == .helperMissing { return "System Helper Required" }
            if presentation.installationStep == .helperAwaitingApproval { return "Approval Required" }
        }
        if presentation.controlState == .monitorOnly { return "Monitor only" }
        if !fanControlReady { return "Not Set Up" }
        if boost { return "Boost active" }
        return curveModel.isActive ? "Curve active" : "Off"
    }

    var fanControlStateColor: Color {
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
        return sidebarProminentActionButton(
            title: boostButtonLabel,
            systemImage: "bolt.fill",
            tint: Color(nsColor: .systemOrange),
            active: boost,
            isBusy: pendingAction == targetAction,
            action: {
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
        )
        .help(boostHelp)
    }

    private var boostButtonLabel: String {
        if pendingAction == .enableBoost { return "Boosting Fans" }
        if pendingAction == .disableBoost { return "Stopping Boost" }
        return boost ? "Stop Boost" : "Boost Fans"
    }

    private func sidebarProminentActionButton(
        title: String,
        systemImage: String?,
        tint: Color,
        active: Bool,
        isBusy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            styledSidebarProminentActionButton(
                title: title,
                systemImage: systemImage,
                tint: tint,
                active: active,
                isBusy: isBusy,
                action: action
            )
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(!isBusy)
    }

    @ViewBuilder
    private func styledSidebarProminentActionButton(
        title: String,
        systemImage: String?,
        tint: Color,
        active: Bool,
        isBusy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        sidebarProminentActionButtonBody(
            title: title,
            systemImage: systemImage,
            tint: tint,
            active: active,
            isBusy: isBusy,
            action: action
        )
        .buttonStyle(.plain)
        .background {
            Capsule()
                .fill(active ? tint : tint.opacity(0.12))
        }
        .overlay(
            Capsule()
                .stroke(tint.opacity(active ? 0 : 0.45), lineWidth: 0.8)
        )
    }

    private func sidebarProminentActionButtonBody(
        title: String,
        systemImage: String?,
        tint: Color,
        active: Bool,
        isBusy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !isBusy else { return }
            action()
        } label: {
            sidebarProminentActionButtonLabel(
                title: title,
                systemImage: systemImage,
                tint: tint,
                active: active,
                isBusy: isBusy
            )
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func sidebarProminentActionButtonLabel(
        title: String,
        systemImage: String?,
        tint: Color,
        active: Bool,
        isBusy: Bool
    ) -> some View {
        ZStack {
            if isBusy {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(active ? Color.white : tint)
                    Text(title)
                }
                .foregroundStyle(active ? Color.white : Color.primary)
            } else {
                Text(title)
                    .foregroundStyle(active ? Color.white : Color.primary)
                if let systemImage {
                    HStack {
                        Image(systemName: systemImage)
                            .foregroundStyle(active ? Color.white : tint)
                        Spacer()
                    }
                    .padding(.leading, 14)
                }
            }
        }
        .font(.callout.weight(.medium))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func legacySidebarProminentActionButton(
        title: String,
        systemImage: String?,
        tint: Color,
        active: Bool,
        isBusy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if active {
            sidebarProminentActionButtonBody(
                title: title,
                systemImage: systemImage,
                tint: tint,
                active: active,
                isBusy: isBusy,
                action: action
            )
            .buttonStyle(.borderedProminent)
            .tint(tint)
        } else {
            sidebarProminentActionButtonBody(
                title: title,
                systemImage: systemImage,
                tint: tint,
                active: active,
                isBusy: isBusy,
                action: action
            )
            .buttonStyle(.bordered)
            .tint(tint)
        }
    }

    var boostHelp: String {
        "Pins all fans to 100% (or Overdrive target) while enabled."
    }

    var setupButton: some View {
        Group {
            if let (label, action) = setupAction {
                let isBusy = setupButtonBusy
                sidebarProminentActionButton(
                    title: setupButtonLabel(fallback: label),
                    systemImage: setupButtonSystemImage,
                    tint: Color.accentColor,
                    active: true,
                    isBusy: isBusy,
                    action: action
                )
                .help(setupHelp)
            } else if installState.step == .checking {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking setup")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var setupButtonSystemImage: String? {
        switch installState.step {
        case .helperMissing:
            return nil
        case .agentMissing:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .agentAwaitingApproval, .helperAwaitingApproval:
            return "arrow.up.forward.app.fill"
        case .ready, .checking:
            return "checkmark.circle.fill"
        }
    }

    private var setupHelp: String {
        switch installState.step {
        case .helperMissing:
            return "Install the helper so Fan Curve can apply fan speeds."
        case .agentMissing:
            return "Enable background control so Fan Curve can keep applying your curve after the app closes."
        case .agentAwaitingApproval, .helperAwaitingApproval:
            return "Open Login Items in System Settings and allow Fan Curve to run in the background."
        case .ready, .checking:
            return ""
        }
    }

    private var setupAction: (String, () -> Void)? {
        switch installState.step {
        case .helperMissing:
            return ("Set Up System Helper", {
                sensorDashboardSidebarLog.notice("sidebar.helper_setup.tapped")
                beginPendingAction(.helperSetup)
                Task {
                    do {
                        try await runtime.registerHelperDaemon()
                    } catch {
                        sensorDashboardSidebarLog.notice(
                            "sidebar.helper_setup.command_failed error=\(error.localizedDescription, privacy: .public) recovery=show-error"
                        )
                        await MainActor.run {
                            installState.lastError = error.localizedDescription
                            completePendingAction(.helperSetup, reason: "command-failed")
                        }
                    }
                }
            })
        case .agentMissing:
            return ("Enable Background Control", {
                sensorDashboardSidebarLog.notice("sidebar.agent_setup.tapped")
                beginPendingAction(.agentSetup)
                installState.registerAgent()
            })
        case .agentAwaitingApproval, .helperAwaitingApproval:
            return ("Open System Settings", {
                sensorDashboardSidebarLog.notice(
                    "sidebar.login_items_settings.tapped step=\(String(describing: installState.step), privacy: .public)"
                )
                beginPendingAction(.openSystemSettings)
                Task {
                    do {
                        try await runtime.openSystemSettings()
                    } catch {
                        sensorDashboardSidebarLog.notice(
                            "sidebar.login_items_settings.agent_command_failed error=\(error.localizedDescription, privacy: .public) recovery=open-from-app"
                        )
                        await MainActor.run {
                            installState.openLoginItemsSettings()
                        }
                    }
                }
            })
        case .ready, .checking:
            return nil
        }
    }

    private var setupButtonBusy: Bool {
        installState.isRegisteringAgent
            || installState.isRegisteringHelper
            || pendingAction == .helperSetup
            || pendingAction == .agentSetup
            || pendingAction == .openSystemSettings
    }

    private func setupButtonLabel(fallback: String) -> String {
        if pendingAction == .helperSetup { return "Setting Up System Helper" }
        if pendingAction == .agentSetup { return "Enabling Background Control" }
        if pendingAction == .openSystemSettings { return "Opening System Settings" }
        if installState.isRegisteringHelper { return "Setting Up System Helper" }
        if installState.isRegisteringAgent { return "Enabling Background Control" }
        return fallback
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
        if presentation.installationStep == .helperMissing { return "System Helper Required" }
        if presentation.installationStep == .agentMissing { return "Background Control Required" }
        if presentation.installationStep == .agentAwaitingApproval
            || presentation.installationStep == .helperAwaitingApproval
        {
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

    var fanControlToggleBusy: Bool {
        if case .setFanControl = pendingAction { return true }
        return false
    }

    var fanControlToggleHelp: String {
        if boost { return "Turn Boost off first to change this." }
        if fanControlToggleBusy { return "Waiting for background control to observe this fan-control change." }
        return ""
    }

    var fanControlBinding: Binding<Bool> {
        Binding(
            get: { curveModel.isActive },
            set: { enabled in
                guard pendingAction == nil else { return }
                sensorDashboardSidebarLog.notice(
                    "sidebar.fan_control.toggled next_enabled=\(enabled, privacy: .public)"
                )
                beginPendingAction(.setFanControl(enabled))
                Task {
                    do {
                        try await runtime.setFanControlEnabled(enabled)
                        await MainActor.run {
                            curveModel.isActive = enabled
                        }
                    } catch {
                        sensorDashboardSidebarLog.notice(
                            "sidebar.fan_control.command_failed enabled=\(enabled, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=keep-current-state"
                        )
                        await MainActor.run {
                            completePendingAction(.setFanControl(enabled), reason: "command-failed")
                        }
                    }
                }
            }
        )
    }

    func beginPendingAction(_ action: SidebarPendingAction) {
        pendingAction = action
        pendingActionStartDate = Date()
        sensorDashboardSidebarLog.notice(
            "sidebar.pending.started action=\(action.logName, privacy: .public)"
        )
    }

    func reconcilePendingAction(reason: String) {
        guard let pendingAction else { return }
        if pendingActionFailed(pendingAction) {
            guard pendingActionMinimumVisibleDurationElapsed() else {
                logPendingActionMinimumDelay(pendingAction, reason: "\(reason)-failed")
                return
            }
            completePendingAction(pendingAction, reason: "\(reason)-failed")
            return
        }
        if pendingActionObserved(pendingAction) {
            guard pendingActionMinimumVisibleDurationElapsed() else {
                logPendingActionMinimumDelay(pendingAction, reason: "\(reason)-observed")
                return
            }
            completePendingAction(pendingAction, reason: "\(reason)-observed")
        }
    }

    func completePendingAction(_ action: SidebarPendingAction, reason: String) {
        guard pendingAction == action else { return }
        pendingAction = nil
        pendingActionStartDate = nil
        sensorDashboardSidebarLog.notice(
            "sidebar.pending.finished action=\(action.logName, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    func pendingActionMinimumVisibleDurationElapsed() -> Bool {
        pendingActionMinimumRemainingNanoseconds() == 0
    }

    func pendingActionMinimumRemainingNanoseconds() -> UInt64 {
        guard let pendingAction else { return 0 }
        let minimumDuration = pendingAction.minimumVisibleDuration
        guard minimumDuration > 0 else { return 0 }
        guard let pendingActionStartDate else { return 0 }
        let elapsedDuration = Date().timeIntervalSince(pendingActionStartDate)
        let remainingDuration = minimumDuration - elapsedDuration
        guard remainingDuration > 0 else { return 0 }
        return UInt64(remainingDuration * 1_000_000_000)
    }

    private func logPendingActionMinimumDelay(_ action: SidebarPendingAction, reason: String) {
        sensorDashboardSidebarLog.debug(
            "sidebar.pending.minimum_duration.waiting action=\(action.logName, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    private func pendingActionObserved(_ action: SidebarPendingAction) -> Bool {
        switch action {
        case .helperSetup:
            return installState.step == .helperAwaitingApproval
                || installState.step == .ready
        case .agentSetup:
            return installState.step != .agentMissing
        case .openSystemSettings:
            return installState.step != .agentAwaitingApproval
                && installState.step != .helperAwaitingApproval
        case .enableBoost:
            return runtime.boostEnabled
        case .disableBoost:
            return !runtime.boostEnabled
        case .setFanControl(let enabled):
            return runtime.curveActive == enabled
        }
    }

    private func pendingActionFailed(_ action: SidebarPendingAction) -> Bool {
        switch action {
        case .helperSetup, .agentSetup, .openSystemSettings:
            return installState.lastError != nil
        case .enableBoost, .disableBoost, .setFanControl:
            return false
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
                        .animation(.easeOut(duration: 0.32), value: roundedValue)
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
                            .animation(.easeOut(duration: 0.32), value: value)
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
