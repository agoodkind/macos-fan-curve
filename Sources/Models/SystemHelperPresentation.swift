//
//  SystemHelperPresentation.swift
//  FanCurve
//
//  Created by Codex <noreply@openai.com> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation

struct SystemHelperPresentation: Equatable {
  private static let registrationRepairDetail =
    "Fan Curve can’t use the System Helper until its registration is repaired. Repair it to read "
    + "temperatures and control your fans."
  private static let approvalRequiredDetail =
    "Allow Fan Curve to run in the background so it can keep applying your fan curve after you close "
    + "the app."

  enum Action: Equatable {
    case openSystemSettings
    case repair
  }

  enum Tone: Equatable {
    case healthy
    case degraded
    case inactive
  }

  let tone: Tone
  let status: String
  let detail: String?
  let actionTitle: String?
  let action: Action?
  let isBusy: Bool

  static func resolve(
    state: SystemHelperRuntimeState,
    repairInFlight: Bool
  ) -> SystemHelperPresentation {
    let presentation = presentation(for: state)
    guard repairInFlight else { return presentation }
    return SystemHelperPresentation(
      tone: presentation.tone,
      status: presentation.status,
      detail: presentation.detail,
      actionTitle: repairTitle(activeIdentity: state.activeIdentity, isBusy: true),
      action: presentation.action,
      isBusy: true
    )
  }

  static func activeVersion(for state: SystemHelperRuntimeState) -> String {
    guard let identity = state.activeIdentity else { return "Unavailable" }
    return version(identity)
  }

  static func activeHash(for state: SystemHelperRuntimeState) -> String {
    state.activeIdentity?.executableHash ?? "Unavailable"
  }

  private static func presentation(
    for state: SystemHelperRuntimeState
  ) -> SystemHelperPresentation {
    switch state {
    case .checking:
      return value(tone: .inactive, status: "Checking", isBusy: true)
    case .running(let active):
      return value(
        tone: .healthy,
        status: "Running",
        actionTitle: repairTitle(activeIdentity: active, isBusy: false),
        action: .repair
      )
    case let .updating(active, bundled):
      return value(
        tone: .degraded,
        status: "Updating",
        detail: versionDetail(active: active, bundled: bundled),
        actionTitle: repairTitle(activeIdentity: active, isBusy: true),
        action: .repair,
        isBusy: true
      )
    case let .outdated(active, bundled):
      return value(
        tone: .degraded,
        status: "Outdated",
        detail: versionDetail(active: active, bundled: bundled),
        actionTitle: repairTitle(activeIdentity: active, isBusy: false),
        action: .repair
      )
    case .registrationNeedsRepair:
      return value(
        tone: .degraded,
        status: "Registration Needs Repair",
        detail: registrationRepairDetail,
        actionTitle: "Install System Helper",
        action: .repair
      )
    case .approvalRequired:
      return value(
        tone: .degraded,
        status: "Approval Required",
        detail: approvalRequiredDetail,
        actionTitle: "Open System Settings",
        action: .openSystemSettings
      )
    case let .repairFailed(active, _, failure):
      return value(
        tone: .degraded,
        status: "Repair Failed",
        detail: failureDetail(failure),
        actionTitle: repairTitle(activeIdentity: active, isBusy: false),
        action: .repair
      )
    case .unavailable(let reason):
      return value(
        tone: .inactive,
        status: "Unavailable",
        detail: reason,
        actionTitle: "Install System Helper",
        action: .repair
      )
    }
  }

  private static func value(
    tone: Tone,
    status: String,
    detail: String? = nil,
    actionTitle: String? = nil,
    action: Action? = nil,
    isBusy: Bool = false
  ) -> SystemHelperPresentation {
    SystemHelperPresentation(
      tone: tone,
      status: status,
      detail: detail,
      actionTitle: actionTitle,
      action: action,
      isBusy: isBusy
    )
  }

  private static func repairTitle(
    activeIdentity: SystemHelperIdentity?,
    isBusy: Bool
  ) -> String {
    if activeIdentity != nil {
      return isBusy ? "Reinstalling System Helper" : "Reinstall System Helper"
    }
    return isBusy ? "Installing System Helper" : "Install System Helper"
  }

  private static func versionDetail(
    active: SystemHelperIdentity?,
    bundled: SystemHelperIdentity
  ) -> String {
    let activeVersion = active.map(version) ?? "Unavailable"
    return "Active version: \(activeVersion). Bundled version: \(version(bundled))."
  }

  private static func version(_ identity: SystemHelperIdentity) -> String {
    "\(identity.version) (build \(identity.build))"
  }

  private static func failureDetail(_ failure: SystemHelperFailure) -> String {
    "\(stageName(failure.stage)) failed: \(failure.reason). \(failure.recovery)."
  }

  private static func stageName(_ stage: SystemHelperFailureStage) -> String {
    switch stage {
    case .disconnect:
      return "Disconnect"
    case .fanReset:
      return "Fan reset"
    case .identityVerification:
      return "Identity verification"
    case .preflight:
      return "Preflight"
    case .reconnect:
      return "Reconnect"
    case .register:
      return "Register"
    case .unregister:
      return "Unregister"
    }
  }
}
