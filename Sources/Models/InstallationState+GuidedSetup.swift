//
//  InstallationState+GuidedSetup.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-09-07.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let guidedSetupLog = AppLog.make(category: "InstallationState")

// MARK: - GuidedSetupProgress

enum GuidedSetupProgress: String {
  case cancelled
  case complete
  case connectingAgent
  case failed
  case failedHelper
  case idle
  case installingHelper
  case verifyingHelper

  var isFailed: Bool {
    self == .failed || self == .failedHelper
  }

  var ownsLifecycle: Bool {
    self != .idle && self != .complete
  }
}

// MARK: - InstallationAgentClient

@MainActor
protocol InstallationAgentClient: Sendable {
  var connectionState: FanCurveAgentConnectionState { get }
  var connectionGeneration: UInt64 { get }
  var runtimeStateGeneration: UInt64? { get }
  var runtimeState: RuntimeState { get }
  var helperReachable: Bool { get }

  func installOrRepairHelper() async throws
  func refreshCurrentState() async throws
  func openSystemSettings() async throws
}

// MARK: - FanCurveAgentClient + InstallationAgentClient

extension FanCurveAgentClient: InstallationAgentClient {}

// MARK: - Guided setup

extension InstallationState {
  func permitsAgentRefresh(_ context: AgentRefreshContext, bundledHash: String) -> Bool {
    guard !setupActionIsBusy, !isReadingApprovalState,
      setupTask == nil, currentAgentStatus() == .enabled
    else { return false }
    switch setupProgress {
    case .cancelled, .failed:
      return false
    case .idle, .complete:
      return true
    case .connectingAgent, .installingHelper, .verifyingHelper, .failedHelper:
      return context.agentConnected
        && !context.runningHash.isEmpty
        && context.runningHash != bundledHash
        && !agentStartupGracePeriodIsActive()
    }
  }

  func refreshObservedSetup(agentClient: any InstallationAgentClient) async {
    refresh(agentClient: agentClient)
    guard agentConnected, systemHelperState == .approvalRequired,
      !setupProgress.isFailed, setupProgress != .cancelled,
      !isReadingApprovalState, setupTask == nil
    else { return }
    if let retiringGeneration = retiringAgentConnectionGeneration {
      guard agentClient.connectionGeneration != retiringGeneration else { return }
      retiringAgentConnectionGeneration = nil
      guidedSetupLog.notice(
        "setup.approval.connection.replaced generation=\(agentClient.connectionGeneration, privacy: .public) recovery=read-current-agent-state"
      )
    }
    isReadingApprovalState = true
    defer { isReadingApprovalState = false }
    guidedSetupLog.debug("setup.approval.observe.started owner=agent-xpc")
    do {
      try await agentClient.refreshCurrentState()
      refresh(agentClient: agentClient)
      guidedSetupLog.debug("setup.approval.observe.finished owner=agent-xpc")
    } catch {
      guard setupProgress != .cancelled else { return }
      failSetup(error.localizedDescription)
      guidedSetupLog.error(
        "setup.approval.observe.failed reason=\(error.localizedDescription, privacy: .public) recovery=explicit-retry"
      )
    }
  }

  var setupActionIsBusy: Bool {
    isRegisteringAgent || isRegisteringHelper || isOpeningSetupSettings
  }

  var setupActionTitle: String? {
    if setupActionIsBusy { return nil }
    if setupProgress.isFailed { return "Retry Setup" }
    if agentStatus == .requiresApproval { return "Open System Settings" }
    if agentConnected, systemHelperState == .approvalRequired {
      return "Open System Settings"
    }
    if backgroundControlProgress != nil { return nil }
    switch setupProgress {
    case .connectingAgent, .installingHelper, .verifyingHelper:
      return nil
    case .idle, .complete, .cancelled:
      if agentConnected, case .running = systemHelperState { return nil }
      return "Enable Background Control"
    case .failed, .failedHelper:
      return "Retry Setup"
    }
  }

  var setupStatusText: String? {
    if isRegisteringAgent { return "Enabling Background Control" }
    if isRegisteringHelper { return "Installing System Helper" }
    if setupProgress.isFailed { return lastError }
    if agentStatus == .requiresApproval { return "Approve Background Agent in System Settings" }
    if agentConnected, systemHelperState == .approvalRequired {
      return "Approve System Helper in System Settings"
    }
    switch setupProgress {
    case .connectingAgent:
      return agentConnected ? "Checking System Helper" : "Waiting for Background Agent"
    case .installingHelper, .verifyingHelper:
      return "Verifying System Helper"
    case .idle, .complete, .cancelled, .failed, .failedHelper:
      return nil
    }
  }

  func performSetupAction(agentClient: any InstallationAgentClient) {
    guard !setupActionIsBusy else { return }
    if !setupProgress.isFailed, currentAgentStatus() == .requiresApproval {
      if !setupProgress.ownsLifecycle { transitionSetup(to: .connectingAgent) }
      openAgentLoginItemsSettings()
      return
    }
    if !setupProgress.isFailed,
      agentClient.connectionState == .connected,
      agentClient.runtimeState.systemHelper == .approvalRequired
    {
      transitionSetup(to: .verifyingHelper)
      openHelperApproval(agentClient: agentClient)
      return
    }
    beginSetup(agentClient: agentClient)
  }

  func beginSetup(agentClient: any InstallationAgentClient) {
    guard !setupActionIsBusy else { return }
    let retryUnresponsiveAgent = setupProgress.isFailed && agentUnresponsiveNow
    lastError = nil
    setupDefaults.removeObject(forKey: SharedConfigKeys.guidedSetupFailure)
    transitionSetup(to: .connectingAgent)
    let status = currentAgentStatus()
    agentDisconnectedSince = Date()
    if retryUnresponsiveAgent, status == .enabled {
      restartAgent()
      if let lastError {
        failSetup(lastError)
        return
      }
    }
    if status != .enabled, status != .requiresApproval {
      isRegisteringAgent = true
      let result = registerAgentService()
      isRegisteringAgent = false
      let observedStatus = currentAgentStatus()
      if let error = result.errorRequiringRetry(status: observedStatus) {
        failSetup(error)
        return
      }
      lastAgentServiceRegisterDate = Date()
      setupDefaults.set(
        serviceRegistrationFingerprints().agent,
        forKey: SharedConfigKeys.agentRegistrationFingerprint
      )
      guidedSetupLog.notice(
        "setup.agent.registered status=\(observedStatus.description, privacy: .public)")
    }
    refresh(agentClient: agentClient)
  }

  func continueSetup(agentClient: any InstallationAgentClient) {
    guard setupTask == nil, !setupActionIsBusy else { return }
    if setupProgress == .failedHelper {
      guard agentConnected else { return }
      switch systemHelperState {
      case .approvalRequired, .running:
        lastError = nil
        setupDefaults.removeObject(forKey: SharedConfigKeys.guidedSetupFailure)
        transitionSetup(to: .verifyingHelper)
      default:
        return
      }
    }
    switch setupProgress {
    case .idle, .complete, .cancelled, .failed, .failedHelper:
      return
    case .connectingAgent, .installingHelper, .verifyingHelper:
      break
    }
    if agentStatus == .requiresApproval { return }
    guard agentStatus == .enabled else {
      failSetup("Background Agent is disabled. Retry Setup to enable it.")
      return
    }
    guard agentConnected else {
      if agentUnresponsiveNow {
        failSetup("Background Agent did not connect. Retry Setup to check it again.")
      }
      return
    }
    switch systemHelperState {
    case .running:
      lastError = nil
      setupDefaults.removeObject(forKey: SharedConfigKeys.guidedSetupFailure)
      transitionSetup(to: .complete)
    case .approvalRequired:
      transitionSetup(to: .verifyingHelper)
    case .checking, .updating:
      break
    case .outdated, .registrationNeedsRepair, .unavailable, .repairFailed:
      if setupProgress == .connectingAgent {
        installGuidedHelper(agentClient: agentClient)
      } else {
        failSetup(helperSetupFailure)
      }
    }
  }

  private var helperSetupFailure: String {
    switch systemHelperState {
    case .unavailable(let reason), .registrationNeedsRepair(let reason):
      return reason
    case .repairFailed(_, _, let failure):
      return failure.reason
    default:
      return "System Helper did not become ready. Retry Setup to check it again."
    }
  }

  func installGuidedHelper(agentClient: any InstallationAgentClient) {
    lastError = nil
    setupDefaults.removeObject(forKey: SharedConfigKeys.guidedSetupFailure)
    transitionSetup(to: .installingHelper)
    isRegisteringHelper = true
    guidedSetupLog.notice("setup.helper.install.started owner=agent-xpc")
    setupTask = Task {
      defer {
        isRegisteringHelper = false
        setupTask = nil
        refresh(agentClient: agentClient)
      }
      var commandError: Error?
      do {
        try await agentClient.installOrRepairHelper()
      } catch {
        commandError = error
        guidedSetupLog.notice(
          "setup.helper.command.failed reason=\(error.localizedDescription, privacy: .public) recovery=read-current-state"
        )
      }
      guard !Task.isCancelled else { return }
      do {
        try await agentClient.refreshCurrentState()
        guard !Task.isCancelled else { return }
        switch agentClient.runtimeState.systemHelper {
        case .approvalRequired, .running:
          transitionSetup(to: .verifyingHelper)
        default:
          if let commandError {
            failSetup(commandError.localizedDescription, progress: .failedHelper)
          } else {
            transitionSetup(to: .verifyingHelper)
          }
        }
        guidedSetupLog.notice("setup.helper.install.finished recovery=verify-agent-runtime")
      } catch {
        guard !Task.isCancelled else { return }
        failSetup(error.localizedDescription)
      }
    }
  }

  func openHelperApproval(agentClient: any InstallationAgentClient) {
    guard !setupActionIsBusy else { return }
    lastError = nil
    setupDefaults.removeObject(forKey: SharedConfigKeys.guidedSetupFailure)
    transitionSetup(to: .verifyingHelper)
    isOpeningSetupSettings = true
    setupTask = Task {
      defer {
        setupTask = nil
        isOpeningSetupSettings = false
      }
      do {
        try await agentClient.openSystemSettings()
        guidedSetupLog.notice("setup.helper.approval.opened owner=agent-xpc")
      } catch {
        guard !Task.isCancelled else { return }
        failSetup(error.localizedDescription)
      }
    }
  }

  func cancelSetup() {
    setupTask?.cancel()
    transitionSetup(to: .cancelled)
    setupDefaults.removeObject(forKey: SharedConfigKeys.guidedSetupFailure)
    lastError = nil
    guidedSetupLog.notice(
      "setup.cancelled reason=user-disabled-agent recovery=wait-for-explicit-setup")
  }

  func transitionSetup(to progress: GuidedSetupProgress) {
    guard progress != setupProgress else { return }
    let previous = setupProgress
    setupProgress = progress
    if progress.isFailed || progress == .cancelled {
      setBackgroundControlProgress(nil)
    } else if progress == .connectingAgent {
      setBackgroundControlProgress(.connecting)
    }
    setupDefaults.set(progress.rawValue, forKey: SharedConfigKeys.guidedSetupProgress)
    guidedSetupLog.notice(
      "setup.stage.changed from=\(previous.rawValue, privacy: .public) to=\(progress.rawValue, privacy: .public)"
    )
  }

  func failSetup(_ reason: String, progress: GuidedSetupProgress = .failed) {
    lastError = reason
    setupDefaults.set(reason, forKey: SharedConfigKeys.guidedSetupFailure)
    transitionSetup(to: progress)
    guidedSetupLog.error("setup.failed reason=\(reason, privacy: .public) recovery=explicit-retry")
  }

  func restartAgent() {
    guard !isRegisteringAgent, setupTask == nil else { return }
    isRegisteringAgent = true
    defer { isRegisteringAgent = false }
    guidedSetupLog.notice("agent.restart.started")
    transitionSetup(to: .connectingAgent)
    setupDefaults.removeObject(forKey: SharedConfigKeys.guidedSetupFailure)
    agentDisconnectedSince = Date()
    let result = refreshRegisteredAgent()
    agentStatus = currentAgentStatus()
    if agentStatus == .requiresApproval { setBackgroundControlProgress(nil) }
    if let error = result.errorRequiringRetry(status: agentStatus) {
      failSetup(error)
      guidedSetupLog.error(
        "agent.restart.failed reason=\(error, privacy: .public) recovery=explicit-retry")
      return
    }
    lastError = nil
    lastAgentServiceRegisterDate = Date()
    guidedSetupLog.notice(
      "agent.restart.finished status=\(agentStatus.description, privacy: .public)")
  }
}
