//
//  InstallationState+BackgroundControlProgress.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-09-12.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let backgroundControlProgressLog = AppLog.make(category: "InstallationState")

enum BackgroundControlProgress: String {
  case connecting
  case updating
}

// MARK: - Background control presentation

extension InstallationState {
  func refreshBackgroundControlProgress(agentClient: any InstallationAgentClient) {
    if backgroundControlObservedGeneration != agentClient.connectionGeneration {
      backgroundControlObservedGeneration = agentClient.connectionGeneration
      backgroundControlSampleWaitStartedAt = nil
    }
    setBackgroundControlProgress(resolveBackgroundControlProgress(agentClient: agentClient))
  }

  func setBackgroundControlProgress(_ progress: BackgroundControlProgress?) {
    guard backgroundControlProgress != progress else { return }
    let previous = backgroundControlProgress
    if progress == .updating {
      backgroundControlUpdateStartedAt = Date()
    } else {
      backgroundControlUpdateStartedAt = nil
    }
    backgroundControlProgress = progress
    backgroundControlProgressLog.notice(
      "background_control.progress.changed from=\(previous?.rawValue ?? "none", privacy: .public) to=\(progress?.rawValue ?? "none", privacy: .public)"
    )
  }

  private func resolveBackgroundControlProgress(
    agentClient: any InstallationAgentClient
  ) -> BackgroundControlProgress? {
    guard canShowBackgroundControlProgress(agentClient: agentClient) else { return nil }
    let expectedHash = bundledAgentHash()
    let hashKnown = !agentExecutableHash.isEmpty && agentExecutableHash != "n/a"
    let hashMismatch = hashKnown && agentExecutableHash != expectedHash
    let replacingHelper: Bool
    switch systemHelperState {
    case .updating, .outdated:
      replacingHelper = true
    default:
      replacingHelper = false
    }

    let waitingProgress: BackgroundControlProgress =
      hashMismatch || !agentSnapshotCompatible || backgroundControlRetiringGeneration != nil
        || replacingHelper ? .updating : .connecting
    let updateRequired = waitingProgress == .updating
    guard backgroundControlProgress != nil || updateRequired else { return nil }
    guard agentConnected else {
      return agentUnresponsiveNow ? nil : waitingProgress
    }
    if let retiredGeneration = backgroundControlRetiringGeneration,
      agentClient.connectionGeneration == retiredGeneration
    {
      return .updating
    }
    guard agentClient.runtimeStateGeneration == agentClient.connectionGeneration else {
      return waitingProgress
    }
    guard !hashMismatch, agentSnapshotCompatible else { return .updating }
    guard case .running = systemHelperState else { return waitingProgress }

    switch agentClient.runtimeState.health {
    case .degraded(reason: .agentReportedFailure),
      .degraded(reason: .helperUnavailable), .degraded(reason: .setupIncomplete):
      return nil
    case .healthy, .ownershipPreempted, .stale,
      .degraded(reason: .snapshotUnavailable):
      break
    }
    let now = Date()
    guard let snapshot = usableSnapshot(from: agentClient.runtimeState, now: now)
    else { return progressWhileWaitingForFirstSample(waitingProgress, now: now) }
    guard snapshotFollowsUpdate(snapshot) else { return .updating }
    guard currentIdentityAndHeartbeat(expectedHash: expectedHash, now: now) else {
      return waitingProgress
    }
    backgroundControlSampleWaitStartedAt = nil
    backgroundControlRetiringGeneration = nil
    return nil
  }

  private func canShowBackgroundControlProgress(
    agentClient: any InstallationAgentClient
  ) -> Bool {
    guard lastError == nil, !setupProgress.isFailed, setupProgress != .cancelled else {
      return false
    }
    guard agentStatus == .enabled else { return false }
    if case .failed = agentClient.connectionState { return false }
    switch systemHelperState {
    case .approvalRequired, .registrationNeedsRepair, .unavailable, .repairFailed:
      return false
    case .checking, .running, .updating, .outdated:
      return true
    }
  }

  private func usableSnapshot(from runtimeState: RuntimeState, now: Date) -> AgentSnapshot? {
    guard let snapshot = runtimeState.snapshot else { return nil }
    let age = now.timeIntervalSince(snapshot.timestamp)
    guard age < FanCurveAgentClientConstants.snapshotFreshnessWindow else { return nil }
    guard snapshot.governingTemperatureC > 0, !snapshot.fans.isEmpty else { return nil }
    return snapshot
  }

  private func snapshotFollowsUpdate(_ snapshot: AgentSnapshot) -> Bool {
    guard let updateStartedAt = backgroundControlUpdateStartedAt else { return true }
    return snapshot.timestamp >= updateStartedAt
  }

  private func currentIdentityAndHeartbeat(expectedHash: String, now: Date) -> Bool {
    guard !agentExecutableHash.isEmpty, expectedHash != "n/a" else { return false }
    guard agentExecutableHash == expectedHash, agentLastTickEpoch > 0 else { return false }
    return now.timeIntervalSince1970 - agentLastTickEpoch < agentUnresponsiveRefreshInterval
  }

  private func progressWhileWaitingForFirstSample(
    _ progress: BackgroundControlProgress,
    now: Date
  ) -> BackgroundControlProgress? {
    if backgroundControlSampleWaitStartedAt == nil {
      backgroundControlSampleWaitStartedAt = now
    }
    guard let startedAt = backgroundControlSampleWaitStartedAt else { return progress }
    return now.timeIntervalSince(startedAt) < agentStartupGraceInterval ? progress : nil
  }
}
