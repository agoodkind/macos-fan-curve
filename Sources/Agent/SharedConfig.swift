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

  // MARK: - Writes (agent status)

  func writeAgentStatus(pid: Int32, lastTick: Date) {
    defaults.set(Int(pid), forKey: SharedConfigKeys.agentPID)
    defaults.set(lastTick.timeIntervalSince1970, forKey: SharedConfigKeys.agentLastTick)
  }

  func clearAgentStatus() {
    defaults.removeObject(forKey: SharedConfigKeys.agentPID)
    defaults.removeObject(forKey: SharedConfigKeys.agentLastTick)
  }
}
