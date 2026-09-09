//
//  SensorDashboardSidebar+Setup.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-05-10.
//  Copyright © 2026, all rights reserved.
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
        .accessibilityIdentifier(AppAccessibilityIdentifier.Setup.sidebarAction)
      } else if let status = installState.setupStatusText {
        HStack(spacing: SensorDashboardSidebarSetupConstants.checkingStatusRowSpacing) {
          ProgressView()
            .controlSize(.small)
          Text(status)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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
      return "arrow.triangle.2.circlepath.circle.fill"
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
      return helperPresentation.detail
        ?? "Install the helper so Fan Curve can apply fan speeds."
    case .agentMissing:
      return
        "Enable background control so Fan Curve can keep applying your curve after the app closes."
    case .agentAwaitingApproval:
      return
        "Open Login Items in System Settings and allow Fan Curve to run in the background."
    case .helperAwaitingApproval:
      return helperPresentation.detail ?? "Open System Settings to allow the System Helper."
    case .ready, .checking:
      return ""
    }
  }

  private var setupAction: (String, () -> Void)? {
    guard let title = installState.setupActionTitle else { return nil }
    return (
      title,
      {
        sensorDashboardSidebarSetupLog.notice("sidebar.setup.tapped")
        installState.performSetupAction(agentClient: runtime)
      }
    )
  }

  private var setupButtonBusy: Bool {
    installState.setupActionIsBusy
  }

  private func setupButtonLabel(fallback: String) -> String {
    installState.setupActionTitle ?? fallback
  }

  private var helperPresentation: SystemHelperPresentation {
    SystemHelperPresentation.resolve(
      state: installState.systemHelperState,
      repairInFlight: installState.isRegisteringHelper
    )
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
