//
//  InstallationState.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Combine
import Foundation
import ServiceManagement

private let log = AppLog.make(category: "InstallationState")

private enum InstallationStateConstants {
  static let agentLiveFreshnessWindow: TimeInterval = 10
  static let monitoringPollInterval: TimeInterval = 2.0
}

/// Tracks whether the privileged helper and background agent are installed
/// and running. Drives the inline onboarding flow in the GUI.
@MainActor
final class InstallationState: ObservableObject {
  enum Step: Equatable {
    case checking
    case helperMissing
    case helperAwaitingApproval
    case agentMissing
    case agentAwaitingApproval
    case ready
  }

  @Published var step: Step = .checking
  @Published var lastError: String?
  @Published var helperReachable: Bool = false
  @Published var helperRawStatus: Int = 0
  @Published var agentRawStatus: Int = 0
  /// Timestamp of the Agent's last successful tick, read from the shared
  /// UserDefaults suite on each refresh. 0 when unset.
  @Published var agentLastTickEpoch: Double = 0
  /// Last error string reported by the Agent, empty when the last tick
  /// succeeded or the Agent has never written one.
  @Published var agentLastError: String = ""
  @Published var agentExecutableHash: String = ""
  @Published var agentSnapshotSchemaVersion: Int?
  @Published private(set) var isRegisteringAgent = false
  @Published private(set) var isRegisteringHelper = false

  private var timer: Timer?
  var lastAutoRefreshAttemptedHash: String?
  var lastAutoRefreshAttemptDate: Date?
  let agentRefreshRetryInterval: TimeInterval = 30
  var lastAutoRegisterAttemptDate: Date?
  let agentAutoRegisterRetryInterval: TimeInterval = 30
  var lastAgentServiceRegisterDate: Date?
  let agentStartupGraceInterval: TimeInterval = 5

  /// Convenience computed helpers for the Settings UI.
  var agentEnabled: Bool {
    guard #available(macOS 13.0, *) else { return false }
    return SMAppService.Status(rawValue: agentRawStatus) == .enabled
  }

  var helperEnabled: Bool {
    guard #available(macOS 13.0, *) else { return false }
    return SMAppService.Status(rawValue: helperRawStatus) == .enabled
  }

  var helperNeedsRepair: Bool {
    step == .helperMissing && helperReachable
  }

  var helperApprovalPending: Bool {
    step == .helperAwaitingApproval
  }

  /// True when the Agent is registered AND has written a tick within the
  /// freshness window. "Registered but silent" means the process died or
  /// is hung, which is what the user sees as "fan control stopped".
  var agentLive: Bool {
    guard agentEnabled else { return false }
    let lastTick = Date(timeIntervalSince1970: agentLastTickEpoch)
    return agentLastTickEpoch > 0
      && Date().timeIntervalSince(lastTick)
        < InstallationStateConstants.agentLiveFreshnessWindow
  }

  var agentSnapshotCompatible: Bool {
    guard let agentSnapshotSchemaVersion else { return true }
    return agentSnapshotSchemaVersion == AgentSnapshot.currentSchemaVersion
  }

  func startMonitoring(agentClient: FanCurveAgentClient) {
    Task { await refresh(agentClient: agentClient) }
    timer?.invalidate()
    timer = Timer.scheduledTimer(
      withTimeInterval: InstallationStateConstants.monitoringPollInterval,
      repeats: true
    ) { [weak self] _ in
      Task { @MainActor in
        if let self {
          await self.refresh(agentClient: agentClient)
        }
      }
    }
  }

  func stopMonitoring() {
    timer?.invalidate()
    timer = nil
  }

  func refreshOnce(agentClient: FanCurveAgentClient) async {
    await refresh(agentClient: agentClient)
  }

  /// Attempts to register the agent via SMAppService. Idempotent.
  /// Opens System Settings if approval is required.
  func registerAgent() {
    guard #available(macOS 13.0, *) else { return }
    guard !isRegisteringAgent else {
      log.notice(
        "agent.register.skipped reason=registration-in-progress recovery=keep-current-registration"
      )
      return
    }
    isRegisteringAgent = true
    lastError = nil
    log.notice("agent.register.started")
    Task {
      defer {
        isRegisteringAgent = false
        log.notice("agent.register.finished")
      }
      let result = await Self.registerAgentService()
      log.notice(
        "agent.register.requested plist=\(generatedAgentPlistName, privacy: .public) status=\(result.statusBefore, privacy: .public)"
      )

      if let errorDescription = result.errorDescription {
        lastError = errorDescription
        log.error(
          "agent.register.failed error=\(errorDescription, privacy: .public) recovery=show-login-item-error"
        )
        return
      }

      lastAgentServiceRegisterDate = Date()
      let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
      suite.set(
        serviceRegistrationFingerprints().agent,
        forKey: SharedConfigKeys.agentRegistrationFingerprint
      )
      lastError = nil
      log.notice(
        "agent.register.done status=\(result.statusAfterRegister ?? "unknown", privacy: .public)"
      )
    }
  }

  func registerHelperDaemon(agentClient: FanCurveAgentClient) {
    guard !isRegisteringHelper else {
      log.notice(
        "helper.register.skipped reason=registration-in-progress recovery=keep-current-registration"
      )
      return
    }
    isRegisteringHelper = true
    lastError = nil
    log.notice("helper.register.started owner=app")
    Task {
      defer {
        isRegisteringHelper = false
        log.notice("helper.register.finished")
      }
      let result = await Self.registerHelperService()
      log.notice(
        "helper.register.requested plist=\(generatedHelperDaemonPlistName, privacy: .public) status=\(result.statusBefore, privacy: .public)"
      )

      if let errorDescription = result.errorDescription {
        lastError = errorDescription
        log.error(
          "helper.register.failed owner=app error=\(errorDescription, privacy: .public) recovery=show-login-item-error"
        )
        return
      }

      let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
      suite.set(
        serviceRegistrationFingerprints().helper,
        forKey: SharedConfigKeys.helperRegistrationFingerprint
      )
      lastError = nil
      log.notice(
        "helper.register.done owner=app status=\(result.statusAfterRegister ?? "unknown", privacy: .public)"
      )
      await refresh(agentClient: agentClient)
    }
  }

  func openLoginItemsSettings() {
    if #available(macOS 13.0, *) {
      SMAppService.openSystemSettingsLoginItems()
    }
  }

  /// Unregister the agent. Stops it and removes its entry from Login Items.
  func unregisterAgent() {
    guard #available(macOS 13.0, *) else { return }
    Task {
      let result = await Self.unregisterAgentService()
      log.notice(
        "agent.unregister.requested plist=\(generatedAgentPlistName, privacy: .public) status=\(result.statusBefore, privacy: .public)"
      )

      if let errorDescription = result.errorDescription {
        lastError = errorDescription
        log.error(
          "agent.unregister.failed error=\(errorDescription, privacy: .public) recovery=show-login-item-error"
        )
        return
      }

      lastError = nil
      log.notice(
        "agent.unregister.done status=\(result.statusAfterUnregister ?? "unknown", privacy: .public)"
      )
    }
  }

  /// Probes current installation status.
  private func refresh(agentClient: FanCurveAgentClient) async {
    let agentStatus = await currentAgentStatus()
    let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
    let helperOK = agentClient.helperReachable
    let runtimeSetup = agentClient.runtimeState.setup
    let agentConnected = agentClient.connectionState == .connected
    let appBundlePath = Bundle.main.bundleURL.path
    let storedAgentFingerprint = suite.string(
      forKey: SharedConfigKeys.agentRegistrationFingerprint
    )

    helperReachable = helperOK
    helperRawStatus = Self.helperRawStatus(from: runtimeSetup, helperReachable: helperOK)

    agentLastTickEpoch = suite.double(forKey: SharedConfigKeys.agentLastTick)
    agentExecutableHash = suite.string(forKey: SharedConfigKeys.agentExecutableHash) ?? ""
    agentLastError = suite.string(forKey: SharedConfigKeys.agentLastError) ?? ""
    agentSnapshotSchemaVersion = AgentSnapshotStore.storedSchemaVersion(defaults: suite)

    let resolvedAgentStatus = await resolveAgentStatus(
      agentStatus: agentStatus,
      agentConnected: agentConnected,
      appBundlePath: appBundlePath,
      applyInBackground: suite.bool(forKey: SharedConfigKeys.applyInBackground),
      storedFingerprint: storedAgentFingerprint
    )
    let visibleAgentStatus = Self.visibleAgentStatus(
      serviceStatus: resolvedAgentStatus,
      agentConnected: agentConnected
    )
    agentRawStatus = visibleAgentStatus.rawValue

    let fingerprints = serviceRegistrationFingerprints()
    if resolvedAgentStatus == .enabled {
      await refreshAgentIfNeeded(
        AgentRefreshContext(
          agentConnected: agentConnected,
          runningHash: agentExecutableHash,
          snapshotSchemaVersion: agentSnapshotSchemaVersion,
          storedFingerprint: storedAgentFingerprint,
          expectedFingerprint: fingerprints.agent,
          defaults: suite)
      )
    }

    if resolvedAgentStatus == .requiresApproval, !agentConnected {
      step = .agentAwaitingApproval
      return
    }

    if resolvedAgentStatus != .enabled {
      if !agentConnected {
        step = .agentMissing
        return
      }

      log.notice(
        "agent.status.disagrees smappservice=\(resolvedAgentStatus.rawValue, privacy: .public) xpc=connected recovery=use-runtime-state"
      )
    }

    guard agentConnected else {
      log.debug(
        "agent.xpc.unavailable connection=\(String(describing: agentClient.connectionState), privacy: .public) recovery=wait-for-agent-runtime-state"
      )
      step = .checking
      return
    }

    step = Self.installationStep(from: runtimeSetup)
  }

  private func resolveAgentStatus(
    agentStatus: SMAppService.Status,
    agentConnected: Bool,
    appBundlePath: String,
    applyInBackground: Bool,
    storedFingerprint: String?
  ) async -> SMAppService.Status {
    guard !agentConnected else { return agentStatus }
    return await autoRegisterAgentIfNeeded(
      agentStatus: agentStatus,
      appBundlePath: appBundlePath,
      applyInBackground: applyInBackground,
      storedFingerprint: storedFingerprint
    )
  }
}

extension InstallationState {
  @available(macOS 13.0, *)
  nonisolated private static func agentService() -> SMAppService {
    SMAppService.agent(plistName: generatedAgentPlistName)
  }

  @available(macOS 13.0, *)
  nonisolated private static func helperService() -> SMAppService {
    SMAppService.daemon(plistName: generatedHelperDaemonPlistName)
  }

  @available(macOS 13.0, *)
  nonisolated private static func describeAgentStatus(_ status: SMAppService.Status) -> String {
    switch status {
    case .enabled:
      "enabled"
    case .requiresApproval:
      "requiresApproval"
    case .notFound:
      "notFound"
    case .notRegistered:
      "notRegistered"
    default:
      "unknown(\(status.rawValue))"
    }
  }

  @available(macOS 13.0, *)
  nonisolated private static func describeHelperStatus(_ status: SMAppService.Status) -> String {
    describeAgentStatus(status)
  }

  @available(macOS 13.0, *)
  nonisolated static func currentAgentStatusRawValue() async -> Int {
    await MainActor.run {
      agentService().status.rawValue
    }
  }

  @available(macOS 13.0, *)
  nonisolated static func registerAgentService() async -> AgentServiceMutationResult {
    await MainActor.run {
      let service = agentService()
      let statusBefore = describeAgentStatus(service.status)
      let legacyRepair = repairLegacyLaunchAgentIfNeeded()
      if legacyRepair.repaired {
        log.notice(
          "agent.register.legacy_repair.done path=\(legacyRepair.sourcePath, privacy: .public) backup=\(legacyRepair.backupPath ?? "none", privacy: .public) reason=\(legacyRepair.reason, privacy: .public)"
        )
      }
      do {
        try service.register()
        return AgentServiceMutationResult(
          statusBefore: statusBefore,
          statusAfterUnregister: nil,
          statusAfterRegister: describeAgentStatus(service.status),
          errorDescription: nil
        )
      } catch {
        log.error(
          "agent.register.service.failed status=\(statusBefore, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-ui"
        )
        return AgentServiceMutationResult(
          statusBefore: statusBefore,
          statusAfterUnregister: nil,
          statusAfterRegister: nil,
          errorDescription: error.localizedDescription
        )
      }
    }
  }

  @available(macOS 13.0, *)
  nonisolated static func registerHelperService() async -> HelperServiceMutationResult {
    await MainActor.run {
      let service = helperService()
      let statusBefore = describeHelperStatus(service.status)
      do {
        try service.register()
        return HelperServiceMutationResult(
          statusBefore: statusBefore,
          statusAfterRegister: describeHelperStatus(service.status),
          errorDescription: nil
        )
      } catch {
        log.error(
          "helper.register.service.failed status=\(statusBefore, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-ui"
        )
        return HelperServiceMutationResult(
          statusBefore: statusBefore,
          statusAfterRegister: nil,
          errorDescription: error.localizedDescription
        )
      }
    }
  }

  @available(macOS 13.0, *)
  nonisolated static func unregisterAgentService() async -> AgentServiceMutationResult {
    await MainActor.run {
      let service = agentService()
      let statusBefore = describeAgentStatus(service.status)
      do {
        try service.unregister()
        return AgentServiceMutationResult(
          statusBefore: statusBefore,
          statusAfterUnregister: describeAgentStatus(service.status),
          statusAfterRegister: nil,
          errorDescription: nil
        )
      } catch {
        log.error(
          "agent.unregister.service.failed status=\(statusBefore, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-ui"
        )
        return AgentServiceMutationResult(
          statusBefore: statusBefore,
          statusAfterUnregister: nil,
          statusAfterRegister: nil,
          errorDescription: error.localizedDescription
        )
      }
    }
  }

  @available(macOS 13.0, *)
  nonisolated static func refreshRegisteredAgent() async -> AgentServiceMutationResult {
    await MainActor.run {
      let service = agentService()
      let statusBefore = describeAgentStatus(service.status)
      do {
        try service.unregister()
        let statusAfterUnregister = describeAgentStatus(service.status)
        try service.register()
        return AgentServiceMutationResult(
          statusBefore: statusBefore,
          statusAfterUnregister: statusAfterUnregister,
          statusAfterRegister: describeAgentStatus(service.status),
          errorDescription: nil
        )
      } catch {
        log.error(
          "agent.refresh.service.failed status=\(statusBefore, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-refresh-loop"
        )
        return AgentServiceMutationResult(
          statusBefore: statusBefore,
          statusAfterUnregister: nil,
          statusAfterRegister: nil,
          errorDescription: error.localizedDescription
        )
      }
    }
  }

  nonisolated private static func installationStep(from setup: SetupState) -> Step {
    switch setup {
    case .backgroundAgentApproval:
      return .agentAwaitingApproval
    case .backgroundAgentRequired:
      return .agentMissing
    case .helperApproval:
      return .helperAwaitingApproval
    case .helperRequired:
      return .helperMissing
    case .ready:
      return .ready
    }
  }

  nonisolated private static func helperRawStatus(
    from setup: SetupState,
    helperReachable: Bool
  ) -> Int {
    guard #available(macOS 13.0, *) else { return 0 }
    switch setup {
    case .helperApproval:
      return SMAppService.Status.requiresApproval.rawValue
    case .helperRequired:
      return helperReachable
        ? SMAppService.Status.enabled.rawValue
        : SMAppService.Status.notRegistered.rawValue
    case .ready:
      return SMAppService.Status.enabled.rawValue
    case .backgroundAgentApproval, .backgroundAgentRequired:
      return SMAppService.Status.notFound.rawValue
    }
  }

  nonisolated private static func visibleAgentStatus(
    serviceStatus: SMAppService.Status,
    agentConnected: Bool
  ) -> SMAppService.Status {
    guard agentConnected else { return serviceStatus }
    return .enabled
  }
}
