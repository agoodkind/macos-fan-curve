//
//  InstallationState.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Combine
import Foundation

private let log = AppLog.make(category: "InstallationState")

private enum InstallationStateConstants {
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
  @Published var systemHelperState: SystemHelperRuntimeState = .checking
  @Published var agentStatus: ManagedServiceStatus = .notFound
  /// Timestamp of the Agent's last successful tick, read from the shared
  /// UserDefaults suite on each refresh. 0 when unset.
  @Published var agentLastTickEpoch: Double = 0
  /// True while the app holds an open XPC connection to the Agent. Direct
  /// proof the Agent is answering, so it outranks the polled heartbeat.
  @Published var agentConnected: Bool = false
  /// When `refresh()` last read `agentLastTickEpoch`. The heartbeat's age is
  /// measured against this rather than against the current time, so a late
  /// refresh cannot age a healthy Agent into looking dead.
  @Published var lastTickObservedAt: Date?
  /// Last error string reported by the Agent, empty when the last tick
  /// succeeded or the Agent has never written one.
  @Published var agentLastError: String = ""
  @Published var agentExecutableHash: String = ""
  @Published var agentSnapshotSchemaVersion: Int?
  @Published private(set) var isRegisteringAgent = false
  @Published private(set) var isRegisteringHelper = false

  private var timer: Timer?
  /// When the refresh loop first observed the registered Agent without an open
  /// XPC connection. Cleared the moment the Agent answers again.
  var agentDisconnectedSince: Date?
  /// How long a registered Agent may stay unconnected before the refresh loop
  /// treats it as unresponsive and refreshes its registration.
  let agentUnresponsiveRefreshInterval: TimeInterval = 10
  var lastAutoRefreshAttemptedHash: String?
  var lastAutoRefreshAttemptDate: Date?
  let agentRefreshRetryInterval: TimeInterval = 30
  var lastAutoRegisterAttemptDate: Date?
  let agentAutoRegisterRetryInterval: TimeInterval = 30
  var lastAgentServiceRegisterDate: Date?
  let agentStartupGraceInterval: TimeInterval = 5
  let backgroundAgentService: any BackgroundAgentServiceManaging
  let bundledAgentHash: () -> String

  init(
    backgroundAgentService: any BackgroundAgentServiceManaging =
      ServiceManagementAdapters.backgroundAgent(),
    bundledAgentHash: @escaping () -> String = { BuildFingerprint.bundledAgentHash }
  ) {
    self.backgroundAgentService = backgroundAgentService
    self.bundledAgentHash = bundledAgentHash
  }

  /// Convenience computed helpers for the Settings UI.
  var agentEnabled: Bool {
    agentStatus == .enabled
  }

  /// One reading of every signal that speaks to the Agent answering.
  var agentPresenceReading: AgentPresenceResolver.Reading {
    AgentPresenceResolver.Reading(
      registered: agentEnabled,
      connected: agentConnected,
      heartbeatAge: heartbeatAgeAtObservation
    )
  }

  /// Age of the heartbeat measured at the moment it was read, never at render
  /// time. A render-time measurement grows while the app is not polling, which
  /// aged a healthy Agent into looking dead.
  private var heartbeatAgeAtObservation: TimeInterval? {
    guard agentLastTickEpoch > 0, let lastTickObservedAt else { return nil }
    return lastTickObservedAt.timeIntervalSince(
      Date(timeIntervalSince1970: agentLastTickEpoch)
    )
  }

  var agentLivenessEvidence: AgentLivenessEvidence {
    AgentPresenceResolver.evidence(for: agentPresenceReading)
  }

  var agentPresence: AgentPresence {
    AgentPresenceResolver.presence(for: agentPresenceReading)
  }

  /// True when the Agent is registered and something proves it is answering.
  /// "Registered but silent" means the process died or is hung, which is what
  /// the user sees as "fan control stopped".
  var agentLive: Bool {
    agentLivenessEvidence != .unproven
  }

  var agentSnapshotCompatible: Bool {
    guard let agentSnapshotSchemaVersion else { return true }
    return agentSnapshotSchemaVersion == AgentSnapshot.currentSchemaVersion
  }

  func startMonitoring(agentClient: FanCurveAgentClient) {
    Task { refresh(agentClient: agentClient) }
    timer?.invalidate()
    let scheduled = Timer(
      timeInterval: InstallationStateConstants.monitoringPollInterval,
      repeats: true
    ) { [weak self] _ in
      Task { @MainActor in
        if let self {
          self.refresh(agentClient: agentClient)
        }
      }
    }
    // `.common`, not the default mode. A default-mode timer stops firing
    // while the run loop is tracking, which includes scrolling this list and
    // dragging the window, and the refresh must keep running through that.
    RunLoop.main.add(scheduled, forMode: .common)
    timer = scheduled
  }

  func stopMonitoring() {
    timer?.invalidate()
    timer = nil
  }

  func refreshOnce(agentClient: FanCurveAgentClient) {
    refresh(agentClient: agentClient)
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
      let result = registerAgentService()
      log.notice(
        "agent.register.requested plist=\(generatedAgentPlistName, privacy: .public) status=\(result.statusBefore.description, privacy: .public)"
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
        "agent.register.done status=\(result.statusAfterRegister?.description ?? "unknown", privacy: .public)"
      )
    }
  }

  func installOrRepairHelper(agentClient: FanCurveAgentClient) {
    guard !isRegisteringHelper else {
      log.notice(
        "helper.register.skipped reason=registration-in-progress recovery=keep-current-registration"
      )
      return
    }
    isRegisteringHelper = true
    lastError = nil
    log.notice("helper.install.requested owner=agent-xpc")
    Task {
      defer {
        isRegisteringHelper = false
        log.notice("helper.install.finished owner=agent-xpc")
      }
      do {
        try await agentClient.installOrRepairHelper()
      } catch {
        lastError = error.localizedDescription
        log.error(
          "helper.install.failed owner=agent-xpc error=\(error.localizedDescription, privacy: .public) recovery=show-login-item-error"
        )
        return
      }

      log.notice("helper.install.done owner=agent-xpc")
      refresh(agentClient: agentClient)
    }
  }

  func openAgentLoginItemsSettings() {
    lastError = nil
    do {
      try backgroundAgentService.openSystemSettings()
    } catch {
      lastError = error.localizedDescription
      log.error(
        "agent.settings.open_failed error=\(error.localizedDescription, privacy: .public) recovery=show-login-item-error"
      )
    }
  }

  /// Unregister the agent. Stops it and removes its entry from Login Items.
  func unregisterAgent() {
    guard #available(macOS 13.0, *) else { return }
    Task {
      let result = unregisterAgentService()
      log.notice(
        "agent.unregister.requested plist=\(generatedAgentPlistName, privacy: .public) status=\(result.statusBefore.description, privacy: .public)"
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
        "agent.unregister.done status=\(result.statusAfterUnregister?.description ?? "unknown", privacy: .public)"
      )
    }
  }

  /// Takes one reading of everything the Agent reports about itself.
  ///
  /// `lastTickObservedAt` is stamped here, in the same breath as the heartbeat
  /// it describes, so the pair always agree. Reading the heartbeat now and
  /// dating it later is what let a late refresh look like a dead Agent.
  private func adoptAgentSignals(connected: Bool, from suite: UserDefaults) {
    agentConnected = connected
    agentLastTickEpoch = suite.double(forKey: SharedConfigKeys.agentLastTick)
    lastTickObservedAt = Date()
    agentExecutableHash = suite.string(forKey: SharedConfigKeys.agentExecutableHash) ?? ""
    agentLastError = suite.string(forKey: SharedConfigKeys.agentLastError) ?? ""
    agentSnapshotSchemaVersion = AgentSnapshotStore.storedSchemaVersion(defaults: suite)
  }

  /// Probes current installation status.
  private func refresh(agentClient: FanCurveAgentClient) {
    let currentAgentServiceStatus = currentAgentStatus()
    let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
    let helperOK = agentClient.helperReachable
    let runtimeState = agentClient.runtimeState
    let runtimeSetup = runtimeState.setup
    let connectedNow = agentClient.connectionState == .connected
    trackAgentConnection(connectedNow)
    let appBundlePath = Bundle.main.bundleURL.path
    let storedAgentFingerprint = suite.string(
      forKey: SharedConfigKeys.agentRegistrationFingerprint
    )

    helperReachable = helperOK
    adoptSystemHelperState(runtimeState.systemHelper)

    let previousEvidence = agentLivenessEvidence
    let previousPresence = agentPresence
    adoptAgentSignals(connected: connectedNow, from: suite)

    let resolvedAgentStatus = resolveAgentStatus(
      agentStatus: currentAgentServiceStatus,
      agentConnected: connectedNow,
      appBundlePath: appBundlePath,
      applyInBackground: suite.bool(forKey: SharedConfigKeys.applyInBackground),
      storedFingerprint: storedAgentFingerprint
    )
    // Registration alone decides "installed". An open connection proves the
    // Agent is answering, which `agentLivenessEvidence` already reads, so
    // forcing `.enabled` here only let an unregistered Agent claim it was
    // installed.
    agentStatus = resolvedAgentStatus
    logAgentPresenceChange(from: previousPresence, previousEvidence: previousEvidence)

    let fingerprints = serviceRegistrationFingerprints()
    if resolvedAgentStatus == .enabled {
      refreshAgentIfNeeded(
        AgentRefreshContext(
          agentConnected: agentConnected,
          agentUnresponsive: agentUnresponsiveNow,
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
        "agent.status.disagrees smappservice=\(resolvedAgentStatus.description, privacy: .public) xpc=connected recovery=use-runtime-state"
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

  /// Stamps when the Agent connection dropped and clears the stamp on
  /// reconnect, so the unresponsive window measures one continuous outage.
  private func trackAgentConnection(_ connectedNow: Bool) {
    if connectedNow {
      agentDisconnectedSince = nil
    } else if agentDisconnectedSince == nil {
      agentDisconnectedSince = Date()
    }
  }

  /// True when the registered Agent has been unconnected for the whole
  /// unresponsive grace window. A brief disconnect during app or Agent startup
  /// stays inside the window, so healthy launches never trigger a refresh.
  private var agentUnresponsiveNow: Bool {
    guard !agentConnected, let agentDisconnectedSince else { return false }
    return Date().timeIntervalSince(agentDisconnectedSince) >= agentUnresponsiveRefreshInterval
  }

  private func resolveAgentStatus(
    agentStatus: ManagedServiceStatus,
    agentConnected: Bool,
    appBundlePath: String,
    applyInBackground: Bool,
    storedFingerprint: String?
  ) -> ManagedServiceStatus {
    guard !agentConnected else { return agentStatus }
    return autoRegisterAgentIfNeeded(
      agentStatus: agentStatus,
      appBundlePath: appBundlePath,
      applyInBackground: applyInBackground,
      storedFingerprint: storedFingerprint
    )
  }

  private func adoptSystemHelperState(_ state: SystemHelperRuntimeState) {
    systemHelperState = state
    if case .running = state {
      lastError = nil
    }
  }
}

extension InstallationState {
  func registerAgentService() -> AgentServiceMutationResult {
    let statusBefore = backgroundAgentService.status
    let legacyRepair = Self.repairLegacyLaunchAgentIfNeeded()
    if legacyRepair.repaired {
      log.notice(
        "agent.register.legacy_repair.done path=\(legacyRepair.sourcePath, privacy: .public) backup=\(legacyRepair.backupPath ?? "none", privacy: .public) reason=\(legacyRepair.reason, privacy: .public)"
      )
    }
    do {
      try backgroundAgentService.register()
      return AgentServiceMutationResult(
        statusBefore: statusBefore,
        statusAfterUnregister: nil,
        statusAfterRegister: backgroundAgentService.status,
        errorDescription: nil
      )
    } catch {
      log.error(
        "agent.register.service.failed status=\(statusBefore.description, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-ui"
      )
      return AgentServiceMutationResult(
        statusBefore: statusBefore,
        statusAfterUnregister: nil,
        statusAfterRegister: nil,
        errorDescription: error.localizedDescription
      )
    }
  }

  func unregisterAgentService() -> AgentServiceMutationResult {
    let statusBefore = backgroundAgentService.status
    do {
      try backgroundAgentService.unregister()
      return AgentServiceMutationResult(
        statusBefore: statusBefore,
        statusAfterUnregister: backgroundAgentService.status,
        statusAfterRegister: nil,
        errorDescription: nil
      )
    } catch {
      log.error(
        "agent.unregister.service.failed status=\(statusBefore.description, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-ui"
      )
      return AgentServiceMutationResult(
        statusBefore: statusBefore,
        statusAfterUnregister: nil,
        statusAfterRegister: nil,
        errorDescription: error.localizedDescription
      )
    }
  }

  func refreshRegisteredAgent() -> AgentServiceMutationResult {
    let statusBefore = backgroundAgentService.status
    do {
      try backgroundAgentService.unregister()
      let statusAfterUnregister = backgroundAgentService.status
      try backgroundAgentService.register()
      return AgentServiceMutationResult(
        statusBefore: statusBefore,
        statusAfterUnregister: statusAfterUnregister,
        statusAfterRegister: backgroundAgentService.status,
        errorDescription: nil
      )
    } catch {
      log.error(
        "agent.refresh.service.failed status=\(statusBefore.description, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-refresh-loop"
      )
      return AgentServiceMutationResult(
        statusBefore: statusBefore,
        statusAfterUnregister: nil,
        statusAfterRegister: nil,
        errorDescription: error.localizedDescription
      )
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

  /// Records what the Agent row now says and what decided it. Without this
  /// the row's transitions leave no trace, so a user reporting a wrong dot
  /// gives an investigator nothing to work from.
  private func logAgentPresenceChange(
    from previousPresence: AgentPresence,
    previousEvidence: AgentLivenessEvidence
  ) {
    let evidence = agentLivenessEvidence
    let presence = agentPresence
    guard previousPresence != presence || previousEvidence != evidence else {
      return
    }
    // The observation-stamped age, the same value the resolver decided on. A
    // render-time recomputation could log an age the row never saw.
    let heartbeatAge = heartbeatAgeAtObservation ?? -1
    log.notice(
      "agent.presence.changed from=\(previousPresence.rawValue, privacy: .public) to=\(presence.rawValue, privacy: .public) evidence=\(evidence.rawValue, privacy: .public) connected=\(agentConnected, privacy: .public) heartbeatAgeSeconds=\(String(format: "%.1f", heartbeatAge), privacy: .public)"
    )
  }
}
