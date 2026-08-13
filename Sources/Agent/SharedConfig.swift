//
//  SharedConfig.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let sharedConfigLog = AppLog.make(category: "SharedConfig")

private enum SharedConfigConstants {
  static let minimumCurvePointCount: Int = 2
  static let defaultCurveNormalPriority: Int = 10
  static let defaultUserBoostPriority: Int = 50
}

/// Reads config from the shared UserDefaults suite written by the GUI.
/// Writes agent status (PID, last tick) back for GUI health display.
struct SharedConfig {
  let defaults: UserDefaults
  let runningExecutableHash: String

  init() {
    self.init(
      defaults: UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard,
      runningExecutableHash: BuildFingerprint.runningExecutableHash
    )
  }

  init(
    defaults: UserDefaults,
    runningExecutableHash: String = BuildFingerprint.runningExecutableHash
  ) {
    self.defaults = defaults
    self.runningExecutableHash = runningExecutableHash
    LoadAssistStore.migrateLegacyIfNeeded(defaults: self.defaults)
  }

  // MARK: - Reads (populated by GUI)

  func loadCurve() -> [CurvePoint] {
    guard let data = defaults.data(forKey: SharedConfigKeys.curvePoints) else {
      return FanCurveModel.defaultCurve
    }
    do {
      let points = try JSONDecoder().decode([CurvePoint].self, from: data)
      guard points.count >= SharedConfigConstants.minimumCurvePointCount else {
        sharedConfigLog.notice(
          "config.curve.invalid reason=too-few-points recovery=default")
        return FanCurveModel.defaultCurve
      }
      return points
    } catch {
      sharedConfigLog.notice(
        "config.curve.decode_failed error=\(error.localizedDescription, privacy: .public) recovery=default"
      )
      return FanCurveModel.defaultCurve
    }
  }

  func loadInterpolationMode() -> InterpolationMode {
    guard let raw = defaults.string(forKey: SharedConfigKeys.interpolationMode),
      let mode = InterpolationMode(rawValue: raw)
    else { return .catmullRom }
    return mode
  }

  func loadFanResponse() -> FanResponse {
    FanResponse.loadValue(defaults: defaults)
  }

  func loadInferFanResponseFromGraph() -> Bool {
    FanResponse.loadInferFromGraph(defaults: defaults)
  }

  func loadIsActive() -> Bool {
    defaults.bool(forKey: SharedConfigKeys.curveActive)
  }

  func loadBoostEnabled() -> Bool {
    defaults.bool(forKey: SharedConfigKeys.boostEnabled)
  }

  func loadExpandedRangeState() -> ExpandedRangeState {
    ExpandedRangeState(
      overdriveEnabled: defaults.bool(forKey: SharedConfigKeys.overdriveEnabled),
      underdriveEnabled: defaults.bool(forKey: SharedConfigKeys.underdriveEnabled)
    )
  }

  func loadLoadAssistEnabled(_ kind: LoadAssistKind) -> Bool {
    LoadAssistStore.loadEnabled(kind, defaults: defaults)
  }

  func loadLoadAssistCurve(_ kind: LoadAssistKind) -> [CurvePoint] {
    LoadAssistStore.loadPoints(kind, defaults: defaults)
  }

  /// Priority the agent uses for the normal curve write. Matches
  /// `SMCFanPriority.curveNormal` (10) by default.
  func loadCurveNormalPriority() -> Int {
    let stored = defaults.integer(forKey: SharedConfigKeys.curveNormalPriority)
    return stored > 0 ? stored : SharedConfigConstants.defaultCurveNormalPriority
  }

  /// Priority the agent uses when boost is on. Matches
  /// `SMCFanPriority.userBoost` (50) by default.
  func loadUserBoostPriority() -> Int {
    let stored = defaults.integer(forKey: SharedConfigKeys.userBoostPriority)
    return stored > 0 ? stored : SharedConfigConstants.defaultUserBoostPriority
  }

  // MARK: - Writes (agent status)

  /// Publishes process liveness: PID, heartbeat timestamp, and build hash.
  /// Called from `AgentController`'s independent heartbeat cadence, not
  /// from tick completion, so a stalled tick cannot make a healthy process
  /// read as dead. `writeAgentSnapshot` separately carries tick data
  /// freshness via `AgentSnapshot.timestamp`.
  func writeAgentStatus(pid: Int32, lastTick: Date) {
    defaults.set(Int(pid), forKey: SharedConfigKeys.agentPID)
    defaults.set(lastTick.timeIntervalSince1970, forKey: SharedConfigKeys.agentLastTick)
    defaults.set(runningExecutableHash, forKey: SharedConfigKeys.agentExecutableHash)
  }

  func writeAgentSnapshot(_ snapshot: AgentSnapshot) {
    AgentSnapshotStore.save(snapshot, defaults: defaults)
  }

  func writeAgentLastError(_ message: String?) {
    if let message {
      defaults.set(message, forKey: SharedConfigKeys.agentLastError)
    } else {
      defaults.removeObject(forKey: SharedConfigKeys.agentLastError)
    }
  }

  func clearAgentStatus() {
    defaults.removeObject(forKey: SharedConfigKeys.agentPID)
    defaults.removeObject(forKey: SharedConfigKeys.agentLastTick)
    defaults.removeObject(forKey: SharedConfigKeys.agentExecutableHash)
    defaults.removeObject(forKey: SharedConfigKeys.agentLastError)
    AgentSnapshotStore.clear(defaults: defaults)
  }
}
