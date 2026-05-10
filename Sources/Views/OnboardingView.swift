//
//  OnboardingView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import AppLog
import SwiftUI

private let onboardingViewLog = AppLog.make(category: "OnboardingView")

/// Inline onboarding shown when the helper or agent is not installed.
/// Replaces jarring popup alerts with a clean, reassuring flow.
struct OnboardingView: View {
    @ObservedObject var state: InstallationState
    @EnvironmentObject var agentClient: FanCurveAgentClient

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
                HStack(spacing: 8) {
                    if state.isRegisteringAgent || state.isRegisteringHelper {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isRegistering ? installingLabel : label)
                }
                .font(.system(.body, weight: .semibold))
                .frame(minWidth: 180)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isRegistering)
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
        case .checking: return L10n.tr("Checking installation")
        case .helperMissing: return L10n.tr("Install the system helper")
        case .helperAwaitingApproval: return L10n.tr("Approve the helper in System Settings")
        case .agentMissing: return L10n.tr("Enable background fan control")
        case .agentAwaitingApproval: return L10n.tr("Allow FanCurve at login")
        case .ready: return L10n.tr("All set")
        }
    }

    private var subtitleText: String {
        switch state.step {
        case .checking:
            return L10n.tr("Looking for the helper and background agent.")
        case .helperMissing:
            return L10n.tr(
                "FanCurve needs a privileged helper to read temperatures and control fans. "
                    + "Install the helper from this app, then approve it in System Settings if macOS asks."
            )
        case .helperAwaitingApproval:
            return L10n.tr(
                "Open Login Items in System Settings and enable the helper. "
                    + "FanCurve will continue as soon as it is running."
            )
        case .agentMissing:
            return L10n.tr(
                "Install the background agent so FanCurve can apply your curve after the app closes "
                    + "and start again at login."
            )
        case .agentAwaitingApproval:
            return L10n.tr(
                "Open Login Items in System Settings and enable FanCurve so the agent can start at login."
            )
        case .ready:
            return L10n.tr("Everything is running.")
        }
    }

    private var primaryAction: (String, () -> Void)? {
        switch state.step {
        case .helperMissing:
            return (L10n.tr("Install System Helper"), { registerHelper() })
        case .agentMissing:
            return (L10n.tr("Install Background Agent"), { state.registerAgent() })
        case .agentAwaitingApproval, .helperAwaitingApproval:
            return (L10n.tr("Open Login Items"), { openLoginItems() })
        case .ready, .checking:
            return nil
        }
    }

    private func registerHelper() {
        onboardingViewLog.notice("onboarding.helper_register.tapped owner=agent-xpc")
        state.registerHelperDaemon(agentClient: agentClient)
    }

    private func openLoginItems() {
        Task {
            do {
                try await agentClient.openSystemSettings()
            } catch {
                onboardingViewLog.notice(
                    "onboarding.login_items_settings.agent_command_failed error=\(error.localizedDescription, privacy: .public) recovery=open-from-app"
                )
                await MainActor.run {
                    state.openLoginItemsSettings()
                }
            }
        }
    }

    private var isRegistering: Bool {
        state.isRegisteringAgent || state.isRegisteringHelper
    }

    private var installingLabel: String {
        if state.isRegisteringHelper { return L10n.tr("Installing System Helper") }
        return L10n.tr("Installing Background Agent")
    }
}
