//
//  OnboardingView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import SwiftUI

/// Inline onboarding shown when the helper or agent is not installed.
/// Replaces jarring popup alerts with a clean, reassuring flow.
struct OnboardingView: View {
  @ObservedObject var state: InstallationState

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 40)

      VStack(spacing: 24) {
        icon
        title
        subtitle
        action
        errorMessage
      }
      .frame(maxWidth: 480)
      .padding(32)

      Spacer(minLength: 40)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  @ViewBuilder
  private var icon: some View {
    ZStack {
      Circle()
        .fill(Color.accentColor.opacity(0.1))
        .frame(width: 96, height: 96)
      Image(systemName: iconName)
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(Color.accentColor)
    }
  }

  @ViewBuilder
  private var title: some View {
    Text(titleText)
      .font(.system(.title, design: .rounded, weight: .semibold))
      .multilineTextAlignment(.center)
  }

  @ViewBuilder
  private var subtitle: some View {
    Text(subtitleText)
      .font(.body)
      .foregroundColor(.secondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private var action: some View {
    if let (label, handler) = primaryAction {
      Button(action: handler) {
        Text(label)
          .font(.system(.body, weight: .semibold))
          .frame(minWidth: 180)
      }
      .controlSize(.large)
      .buttonStyle(.borderedProminent)
      .keyboardShortcut(.defaultAction)
    } else if state.step == .checking {
      ProgressView()
        .controlSize(.small)
    }
  }

  @ViewBuilder
  private var errorMessage: some View {
    if let err = state.lastError {
      Text(err)
        .font(.footnote)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.top, 8)
    }
  }

  // MARK: - Step-dependent content

  private var iconName: String {
    switch state.step {
    case .checking: return "hourglass"
    case .helperMissing: return "lock.shield"
    case .helperAwaitingApproval: return "hand.raised"
    case .agentMissing, .agentAwaitingApproval: return "gearshape.2"
    case .ready: return "checkmark.circle"
    }
  }

  private var titleText: String {
    switch state.step {
    case .checking: return "Checking installation"
    case .helperMissing: return "Install the system helper"
    case .helperAwaitingApproval: return "Approve the helper in System Settings"
    case .agentMissing: return "Enable background fan control"
    case .agentAwaitingApproval: return "Allow FanCurve at login"
    case .ready: return "All set"
    }
  }

  private var subtitleText: String {
    switch state.step {
    case .checking:
      return "Looking for the helper and background agent."
    case .helperMissing:
      return
        "FanCurve needs a privileged helper to read temperatures and control fans. Install it from the macos-smc-fan project, then return here."
    case .helperAwaitingApproval:
      return "Open Login Items in System Settings and enable the helper. FanCurve will continue as soon as it is running."
    case .agentMissing:
      return
        "The background agent applies your curve even when FanCurve is closed. It starts automatically at login. Click to install."
    case .agentAwaitingApproval:
      return
        "Open Login Items in System Settings and enable FanCurve so the agent can start at login."
    case .ready:
      return "Everything is running."
    }
  }

  private var primaryAction: (String, () -> Void)? {
    switch state.step {
    case .agentMissing:
      return ("Install Background Agent", { state.registerAgent() })
    case .agentAwaitingApproval, .helperAwaitingApproval:
      return ("Open Login Items", { state.openLoginItemsSettings() })
    case .helperMissing:
      return nil
    case .ready, .checking:
      return nil
    }
  }
}
