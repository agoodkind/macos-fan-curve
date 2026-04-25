//
//  SharedConfig.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import Foundation

/// Reads config from the shared UserDefaults suite written by the GUI.
/// Writes agent status (PID, last tick) back for GUI health display.
struct SharedConfig {
  let defaults: UserDefaults

  init() {
    self.defaults = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
    LoadAssistStore.migrateLegacyIfNeeded(defaults: self.defaults)
  }

  // MARK: - Reads (populated by GUI)

  func loadCurve() -> [CurvePoint] {
    guard let data = defaults.data(forKey: SharedConfigKeys.curvePoints),
      let points = try? JSONDecoder().decode([CurvePoint].self, from: data),
      points.count >= 2
    else {
      return FanCurveModel.defaultCurve
    }
    return points
  }

  func loadInterpolationMode() -> InterpolationMode {
    guard let raw = defaults.string(forKey: SharedConfigKeys.interpolationMode),
      let mode = InterpolationMode(rawValue: raw)
    else { return .catmullRom }
    return mode
  }

  func loadIsActive() -> Bool {
    defaults.bool(forKey: SharedConfigKeys.curveActive)
  }

  func loadBoostEnabled() -> Bool {
    defaults.bool(forKey: SharedConfigKeys.boostEnabled)
  }

  func loadLoadFloorEnabled() -> Bool {
    defaults.bool(forKey: SharedConfigKeys.loadFloorEnabled)
  }

  /// Threshold CPU percent (0 to 100) that activates the floor. Defaults
  /// to 70 when unset so a fresh enable has sensible behavior.
  func loadLoadFloorThreshold() -> Double {
    let stored = defaults.double(forKey: SharedConfigKeys.loadFloorThreshold)
    return stored > 0 ? stored : 70
  }

  func loadGpuLoadFloorThreshold() -> Double {
    let stored = defaults.double(forKey: SharedConfigKeys.gpuLoadFloorThreshold)
    return stored > 0 ? stored : 70
  }

  /// Minimum fan percent (0 to 100) applied while the floor is active.
  /// Defaults to 60 when unset.
  func loadLoadFloorPercent() -> Double {
    let stored = defaults.double(forKey: SharedConfigKeys.loadFloorPercent)
    return stored > 0 ? stored : 60
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
    return stored > 0 ? stored : 10
  }

  /// Priority the agent uses when boost is on. Matches
  /// `SMCFanPriority.userBoost` (50) by default.
  func loadUserBoostPriority() -> Int {
    let stored = defaults.integer(forKey: SharedConfigKeys.userBoostPriority)
    return stored > 0 ? stored : 50
  }

  // MARK: - Writes (agent status)

  func writeAgentStatus(pid: Int32, lastTick: Date) {
    defaults.set(Int(pid), forKey: SharedConfigKeys.agentPID)
    defaults.set(lastTick.timeIntervalSince1970, forKey: SharedConfigKeys.agentLastTick)
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
    defaults.removeObject(forKey: SharedConfigKeys.agentLastError)
    AgentSnapshotStore.clear(defaults: defaults)
  }
}
