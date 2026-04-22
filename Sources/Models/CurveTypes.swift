//
//  CurveTypes.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-18.
//  Copyright © 2026
//

import Foundation

struct CurvePoint: Identifiable, Codable, Sendable {
  let id: UUID
  var temperature: Double
  var fanPercent: Double

  init(temperature: Double, fanPercent: Double) {
    self.id = UUID()
    self.temperature = temperature
    self.fanPercent = fanPercent
  }
}

enum InterpolationMode: String, Codable, Sendable {
  case linear
  case catmullRom
}

/// Shared UserDefaults keys. Both GUI and Agent read/write via the shared suite.
enum SharedConfigKeys {
  static let curvePoints = "curvePoints"
  static let interpolationMode = "interpolationMode"
  static let curveActive = "curveActive"
  static let overdriveEnabled = "overdriveEnabled"
  static let underdriveEnabled = "underdriveEnabled"
  static let boostEnabled = "boostEnabled"
  static let loadFloorEnabled = "loadFloorEnabled"
  static let loadFloorThreshold = "loadFloorThreshold"
  static let gpuLoadFloorThreshold = "gpuLoadFloorThreshold"
  static let loadFloorPercent = "loadFloorPercent"
  static let applyInBackground = "applyInBackground"
  static let agentPID = "agentPID"
  static let agentLastTick = "agentLastTick"
  static let agentLastError = "agentLastError"
  static let overdriveTargetRPMMeasured = "overdriveTargetRPMMeasured"
  /// Priority the agent uses for the normal curve write. Default 10.
  static let curveNormalPriority = "curveNormalPriority"
  /// Priority the agent uses when boost is on. Default 50.
  static let userBoostPriority = "userBoostPriority"
}

/// Result of mapping a curve percent to a fan action for one fan.
enum FanCommand: Sendable {
  case setRPM(Float)
  case auto
}
