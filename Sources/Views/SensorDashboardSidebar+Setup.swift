//
//  SensorDashboardSidebar+Setup.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-10.
//  Copyright © 2026
//

import AppLog
import SwiftUI

private let sensorDashboardSidebarSetupLog = AppLog.make(category: "SensorDashboardSidebar")

private enum SensorDashboardSidebarSetupConstants {
    static let checkingStatusRowSpacing: CGFloat = 8
}

extension SensorDashboardSidebar {
    var setupButton: some View {
        Group {
            if let (label, action) = setupAction {
                let isBusy = setupButtonBusy
                sidebarProminentActionButton(
                    SidebarProminentActionConfiguration(
                        title: setupButtonLabel(fallback: label),
                        systemImage: setupButtonSystemImage,
                        tint: Color.accentColor,
                        active: true,
                        isBusy: isBusy
                    ),
                    action: action
                )
                .help(setupHelp)
            } else if installState.step == .checking {
                HStack(spacing: SensorDashboardSidebarSetupConstants.checkingStatusRowSpacing) {
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
            return installState.helperNeedsRepair
                ? "arrow.triangle.2.circlepath.circle.fill"
                : nil
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
            if installState.helperNeedsRepair {
                return
                    "The helper is reachable, but this app install needs to repair its registration."
            }
            return "Install the helper so Fan Curve can apply fan speeds."
        case .agentMissing:
            return
                "Enable background control so Fan Curve can keep applying your curve after the app closes."
        case .agentAwaitingApproval, .helperAwaitingApproval:
            return
                "Open Login Items in System Settings and allow Fan Curve to run in the background."
        case .ready, .checking:
            return ""
        }
    }

    private var setupAction: (String, () -> Void)? {
        switch installState.step {
        case .helperMissing:
            return (
                installState.helperNeedsRepair
                    ? "Reinstall System Helper"
                    : "Install System Helper",
                {
                    sensorDashboardSidebarSetupLog.notice("sidebar.helper_setup.tapped")
                    beginPendingAction(.helperSetup)
                    installState.registerHelperDaemon(agentClient: runtime)
                }
            )
        case .agentMissing:
            return (
                "Enable Background Control",
                {
                    sensorDashboardSidebarSetupLog.notice("sidebar.agent_setup.tapped")
                    beginPendingAction(.agentSetup)
                    installState.registerAgent()
                }
            )
        case .agentAwaitingApproval, .helperAwaitingApproval:
            return (
                "Open System Settings",
                {
                    sensorDashboardSidebarSetupLog.notice(
                        "sidebar.login_items_settings.tapped step=\(String(describing: installState.step), privacy: .public)"
                    )
                    beginPendingAction(.openSystemSettings)
                    Task {
                        do {
                            try await runtime.openSystemSettings()
                        } catch {
                            sensorDashboardSidebarSetupLog.notice(
                                "sidebar.login_items_settings.agent_command_failed error=\(error.localizedDescription, privacy: .public) recovery=open-from-app"
                            )
                            await MainActor.run {
                                installState.openLoginItemsSettings()
                            }
                        }
                    }
                }
            )
        case .ready, .checking:
            return nil
        }
    }

    private var setupButtonBusy: Bool {
        installState.isRegisteringAgent
            || installState.isRegisteringHelper
            || isPendingAction(.helperSetup)
            || isPendingAction(.agentSetup)
            || isPendingAction(.openSystemSettings)
    }

    private func setupButtonLabel(fallback: String) -> String {
        if isPendingAction(.helperSetup) {
            return installState.helperNeedsRepair
                ? "Reinstalling System Helper"
                : "Installing System Helper"
        }
        if isPendingAction(.agentSetup) { return "Enabling Background Control" }
        if isPendingAction(.openSystemSettings) { return "Opening System Settings" }
        if installState.isRegisteringHelper {
            return installState.helperNeedsRepair
                ? "Reinstalling System Helper"
                : "Installing System Helper"
        }
        if installState.isRegisteringAgent { return "Enabling Background Control" }
        return fallback
    }

    var fanControlToggleHelp: String {
        if boost { return "Turn Boost off first to change this." }
        if fanControlToggleBusy {
            return "Waiting for background control to observe this fan-control change."
        }
        return ""
    }

    var fanControlBinding: Binding<Bool> {
        Binding(
            get: { curveModel.isActive },
            set: { enabled in
                guard !hasPendingAction() else { return }
                sensorDashboardSidebarSetupLog.notice(
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
                        sensorDashboardSidebarSetupLog.notice(
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
}
