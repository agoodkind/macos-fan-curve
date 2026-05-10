//
//  SensorDashboardSidebar.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026
//

import AppLog
import SwiftUI

private let sensorDashboardSidebarViewLog = AppLog.make(category: "SensorDashboardSidebar")

struct SensorDashboardSidebar: View {
    @State private var pendingAction: SidebarPendingAction?
    @State private var pendingActionStartDate: Date?
    @ObservedObject var runtime: FanCurveAgentClient
    @ObservedObject var curveModel: FanCurveModel
    @ObservedObject var installState: InstallationState
    let renderMode: AppRenderMode
    let unit: TemperatureUnit
    @Binding var boost: Bool
    let cpuLoadAssistEnabled: Bool
    let gpuLoadAssistEnabled: Bool
    let overdriveEnabled: Bool
    let underdriveEnabled: Bool
    let presentation: DashboardPresentationState

    var fanControlReady: Bool {
        presentation.controlState == .fanControl
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            heroSection
            usageSection
            fansSection
            Divider().opacity(0.15)
            controlsSection
            Spacer()
            statusBlock
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .onChange(of: installState.step) { _ in
            reconcilePendingAction(reason: "installation-step-changed")
        }
        .onChange(of: installState.lastError) { _ in
            reconcilePendingAction(reason: "installation-error-changed")
        }
        .onChange(of: runtime.snapshot) { _ in
            reconcilePendingAction(reason: "runtime-snapshot-changed")
        }
        .task(id: pendingAction) {
            guard let pendingAction else { return }
            do {
                try await Task.sleep(nanoseconds: pendingAction.timeoutNanoseconds)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    completePendingAction(
                        pendingAction,
                        reason: "timeout"
                    )
                }
            } catch {
                sensorDashboardSidebarViewLog.debug(
                    "sidebar.pending.timer.cancelled action=\(pendingAction.logName, privacy: .public) recovery=keep-current-pending-state"
                )
            }
        }
        .task(id: pendingActionStartDate) {
            guard let pendingAction else { return }
            let remainingNanoseconds = pendingActionMinimumRemainingNanoseconds()
            guard remainingNanoseconds > 0 else { return }
            do {
                try await Task.sleep(nanoseconds: remainingNanoseconds)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    reconcilePendingAction(reason: "minimum-duration-elapsed")
                }
            } catch {
                sensorDashboardSidebarViewLog.debug(
                    "sidebar.pending.minimum_timer.cancelled action=\(pendingAction.logName, privacy: .public) recovery=keep-current-pending-state"
                )
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "thermometer.medium")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("CPU Temperature")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(tempColor)
                    .frame(width: 6, height: 6)
            }

            if let displayedTemperature {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(displayedTemperature)")
                        .font(.system(.largeTitle, design: .rounded).weight(.regular))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.38), value: displayedTemperature)
                    Text(unit.symbol)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .center, spacing: 6) {
                    Text("--")
                        .font(.system(.largeTitle, design: .rounded).weight(.regular))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text("unavailable")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var usageSection: some View {
        let assistStates = activeAssistStates
        return VStack(spacing: 10) {
            usageBlock(
                label: "CPU",
                icon: "cpu",
                value: runtimeLoadValue(runtime.cpuLoadPercent),
                tint: Color.accentColor,
                assist: assistStates.first { $0.kind == .cpu }
            )
            usageBlock(
                label: "GPU",
                icon: "memorychip",
                value: runtimeLoadValue(runtime.gpuLoadPercent),
                tint: Color.accentColor.opacity(0.55),
                assist: assistStates.first { $0.kind == .gpu }
            )
        }
    }

    private var fansSection: some View {
        VStack(spacing: 10) {
            if presentation.showsRuntimeStats {
                ForEach(runtime.fans) { fan in
                    fanRow(fan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                }
            }
        }
    }

    private var controlsSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fan Control")
                        .font(.body)
                    Text(fanControlStateLabel)
                        .font(.caption)
                        .foregroundColor(fanControlStateColor)
                    if fanControlReady, curveModel.isActive, !boost {
                        Text(controllerStateLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if presentation.showsFanControlToggle {
                    HStack(spacing: 6) {
                        if fanControlToggleBusy {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Toggle("", isOn: fanControlBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.regular)
                            .tint(Color.accentColor)
                            .disabled(boost || pendingAction != nil)
                            .help(fanControlToggleHelp)
                    }
                }
            }

            if presentation.helperActionVisible {
                setupButton
            } else if presentation.showsBoostControl, curveModel.isActive {
                boostButton
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        )
                    )
            }
        }
    }
}

extension SensorDashboardSidebar {
    func isPendingAction(_ action: SidebarPendingAction) -> Bool {
        pendingAction == action
    }

    func hasPendingAction() -> Bool {
        pendingAction != nil
    }

    var fanControlToggleBusy: Bool {
        if case .setFanControl = pendingAction { return true }
        return false
    }

    func beginPendingAction(_ action: SidebarPendingAction) {
        pendingAction = action
        pendingActionStartDate = Date()
        sensorDashboardSidebarViewLog.notice(
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
        sensorDashboardSidebarViewLog.notice(
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
        sensorDashboardSidebarViewLog.debug(
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
}
