//
//  OnboardingView.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import SwiftUI

private let onboardingViewLog = AppLog.make(category: "OnboardingView")

private enum OnboardingConstants {
  static let outerSpacerMinLength: CGFloat = 40
  static let contentStackSpacing: CGFloat = 20
  static let contentMaxWidth: CGFloat = 560
  static let contentPadding: CGFloat = 32
  static let iconCircleSize: CGFloat = 96
  static let iconFontSize: CGFloat = 40
  static let iconBackgroundOpacity: Double = 0.1
  static let buttonLabelSpacing: CGFloat = 8
  static let buttonMinWidth: CGFloat = 180
  static let errorTopPadding: CGFloat = 8
  static let approvalGuideSpacing: CGFloat = 12
  static let approvalStepSpacing: CGFloat = 10
  static let approvalStepNumberSize: CGFloat = 22
  static let approvalStepNumberFontSize: CGFloat = 11
  static let approvalGuideTopPadding: CGFloat = 2
  static let secondaryTextMaxWidth: CGFloat = 500
}

// MARK: - SetupStepContent

private struct SetupStepContent {
  let iconName: String
  let title: String
  let message: String
  let primaryActionTitle: String?
  let pendingActionTitle: String?
  let approvalSteps: [String]

  static func make(step: InstallationState.Step) -> SetupStepContent {
    switch step {
    case .checking:
      return checking()
    case .helperMissing:
      return helperMissing()
    case .helperAwaitingApproval:
      return helperAwaitingApproval()
    case .agentMissing:
      return agentMissing()
    case .agentAwaitingApproval:
      return agentAwaitingApproval()
    case .ready:
      return ready()
    }
  }

  private static func checking() -> SetupStepContent {
    SetupStepContent(
      iconName: "hourglass",
      title: L10n.tr("Checking setup"),
      message: L10n.tr("Fan Curve is checking the system helper and background agent."),
      primaryActionTitle: nil,
      pendingActionTitle: nil,
      approvalSteps: []
    )
  }

  private static func helperMissing() -> SetupStepContent {
    SetupStepContent(
      iconName: "lock.shield",
      title: L10n.tr("Install the System Helper"),
      message: L10n.tr(
        "Fan Curve uses a system helper to read Mac temperature sensors and send fan "
          + "speed commands. macOS requires your approval before an app can install this "
          + "kind of helper."
      ),
      primaryActionTitle: nil,
      pendingActionTitle: nil,
      approvalSteps: []
    )
  }

  private static func helperAwaitingApproval() -> SetupStepContent {
    SetupStepContent(
      iconName: "hand.raised",
      title: L10n.tr("Allow the System Helper"),
      message: L10n.tr(
        "System Settings is waiting for you to allow the Fan Curve helper. Open Login "
          + "Items & Extensions, turn on Fan Curve, then return here."
      ),
      primaryActionTitle: nil,
      pendingActionTitle: nil,
      approvalSteps: [
        L10n.tr("Click Open System Settings."),
        L10n.tr("In Login Items & Extensions, turn on Fan Curve."),
        L10n.tr("Return to Fan Curve to continue setup when the helper starts."),
      ]
    )
  }

  private static func agentMissing() -> SetupStepContent {
    SetupStepContent(
      iconName: "gearshape.2",
      title: L10n.tr("Enable Background Control"),
      message: L10n.tr(
        "Fan Curve uses a background agent to keep applying your fan curve when the app "
          + "is closed."
      ),
      primaryActionTitle: L10n.tr("Enable Background Control"),
      pendingActionTitle: L10n.tr("Enabling Background Control"),
      approvalSteps: []
    )
  }

  private static func agentAwaitingApproval() -> SetupStepContent {
    SetupStepContent(
      iconName: "gearshape.2",
      title: L10n.tr("Allow Fan Curve in Background"),
      message: L10n.tr(
        "Allow Fan Curve to run in the background so your curve can stay active after "
          + "login."
      ),
      primaryActionTitle: L10n.tr("Open System Settings"),
      pendingActionTitle: L10n.tr("Opening System Settings"),
      approvalSteps: [
        L10n.tr("Click Open System Settings."),
        L10n.tr("In Login Items & Extensions, turn on Fan Curve."),
        L10n.tr("Return to Fan Curve to continue setup when the background agent starts."),
      ]
    )
  }

  private static func ready() -> SetupStepContent {
    SetupStepContent(
      iconName: "checkmark.circle",
      title: L10n.tr("All set"),
      message: L10n.tr("Fan Curve is ready."),
      primaryActionTitle: nil,
      pendingActionTitle: nil,
      approvalSteps: []
    )
  }
}

/// Inline onboarding shown when the helper or agent is not installed.
/// Replaces jarring popup alerts with a clean, reassuring flow.
struct OnboardingView: View {
  @ObservedObject var state: InstallationState
  @EnvironmentObject var agentClient: FanCurveAgentClient

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: OnboardingConstants.outerSpacerMinLength)

      VStack(spacing: OnboardingConstants.contentStackSpacing) {
        icon
        title
        message
        approvalGuide
        action
        errorMessage
      }
      .frame(maxWidth: OnboardingConstants.contentMaxWidth)
      .padding(OnboardingConstants.contentPadding)

      Spacer(minLength: OnboardingConstants.outerSpacerMinLength)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .accessibilityIdentifier(AppAccessibilityIdentifier.Setup.root)
  }

  private var content: SetupStepContent {
    SetupStepContent.make(step: state.step)
  }

  @ViewBuilder
  private var icon: some View {
    ZStack {
      Circle()
        .fill(Color.accentColor.opacity(OnboardingConstants.iconBackgroundOpacity))
        .frame(
          width: OnboardingConstants.iconCircleSize,
          height: OnboardingConstants.iconCircleSize)
      Image(systemName: content.iconName)
        .font(.system(size: OnboardingConstants.iconFontSize, weight: .light))
        .foregroundStyle(Color.accentColor)
    }
  }

  @ViewBuilder
  private var title: some View {
    Text(displayTitle)
      .font(.system(.title, design: .rounded, weight: .semibold))
      .multilineTextAlignment(.center)
      .accessibilityIdentifier(AppAccessibilityIdentifier.Setup.title)
  }

  @ViewBuilder
  private var message: some View {
    Text(displayMessage)
      .font(.body)
      .foregroundColor(.secondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: OnboardingConstants.secondaryTextMaxWidth)
      .accessibilityIdentifier(AppAccessibilityIdentifier.Setup.message)
  }

  @ViewBuilder
  private var approvalGuide: some View {
    if !content.approvalSteps.isEmpty {
      VStack(alignment: .leading, spacing: OnboardingConstants.approvalGuideSpacing) {
        ForEach(Array(content.approvalSteps.enumerated()), id: \.offset) { offset, step in
          HStack(alignment: .firstTextBaseline, spacing: OnboardingConstants.approvalStepSpacing) {
            Text("\(offset + 1)")
              .font(
                .system(
                  size: OnboardingConstants.approvalStepNumberFontSize,
                  weight: .semibold,
                  design: .rounded)
              )
              .foregroundStyle(Color.accentColor)
              .frame(
                width: OnboardingConstants.approvalStepNumberSize,
                height: OnboardingConstants.approvalStepNumberSize
              )
              .background(
                Circle().fill(
                  Color.accentColor.opacity(OnboardingConstants.iconBackgroundOpacity))
              )
              .accessibilityHidden(true)

            Text(step)
              .font(.callout)
              .foregroundStyle(.primary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .frame(maxWidth: OnboardingConstants.secondaryTextMaxWidth, alignment: .leading)
      .padding(.top, OnboardingConstants.approvalGuideTopPadding)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier(AppAccessibilityIdentifier.Setup.approvalGuide)
    }
  }

  @ViewBuilder
  private var action: some View {
    if let (label, handler) = primaryAction {
      Button(action: handler) {
        HStack(spacing: OnboardingConstants.buttonLabelSpacing) {
          if isRegistering {
            ProgressView()
              .controlSize(.small)
          }
          Text(isRegistering ? installingLabel : label)
        }
        .font(.system(.body, weight: .semibold))
        .frame(minWidth: OnboardingConstants.buttonMinWidth)
      }
      .controlSize(.large)
      .buttonStyle(.borderedProminent)
      .keyboardShortcut(.defaultAction)
      .disabled(isRegistering)
      .accessibilityIdentifier(AppAccessibilityIdentifier.Setup.action)
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
        .padding(.top, OnboardingConstants.errorTopPadding)
        .accessibilityIdentifier(AppAccessibilityIdentifier.Setup.error)
    }
  }

  private var primaryAction: (String, () -> Void)? {
    switch state.step {
    case .helperMissing, .helperAwaitingApproval:
      guard let actionTitle = helperPresentation.actionTitle else { return nil }
      return (actionTitle, { performSystemHelperAction(helperPresentation.action) })
    case .agentMissing:
      return (
        content.primaryActionTitle ?? L10n.tr("Enable Background Control"),
        { state.registerAgent() }
      )
    case .agentAwaitingApproval:
      return (
        content.primaryActionTitle ?? L10n.tr("Open System Settings"),
        { state.openAgentLoginItemsSettings() }
      )
    case .ready, .checking:
      return nil
    }
  }

  private func performSystemHelperAction(_ action: SystemHelperPresentation.Action?) {
    switch action {
    case .repair:
      onboardingViewLog.notice("onboarding.helper_register.tapped owner=agent-xpc")
      state.installOrRepairHelper(agentClient: agentClient)
    case .openSystemSettings:
      Task {
        do {
          try await agentClient.openSystemSettings()
        } catch {
          onboardingViewLog.notice(
            "onboarding.login_items_settings.agent_command_failed error=\(error.localizedDescription, privacy: .public) recovery=show-agent-command-error"
          )
          await MainActor.run {
            state.lastError = error.localizedDescription
          }
        }
      }
    case nil:
      return
    }
  }

  private var isRegistering: Bool {
    state.isRegisteringAgent || helperPresentation.isBusy
  }

  private var installingLabel: String {
    if isHelperStep {
      return helperPresentation.actionTitle ?? L10n.tr("Working")
    }
    return content.pendingActionTitle ?? L10n.tr("Working")
  }

  private var displayTitle: String {
    isHelperStep ? helperPresentation.status : content.title
  }

  private var displayMessage: String {
    if isHelperStep, let detail = helperPresentation.detail {
      return detail
    }
    return content.message
  }

  private var isHelperStep: Bool {
    state.step == .helperMissing || state.step == .helperAwaitingApproval
  }

  private var helperPresentation: SystemHelperPresentation {
    SystemHelperPresentation.resolve(
      state: state.systemHelperState,
      repairInFlight: state.isRegisteringHelper
    )
  }
}
