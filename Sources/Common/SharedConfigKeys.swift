//
//  SharedConfigKeys.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

enum SharedConfigKeys {
  static let agentExecutableHash = "agentExecutableHash"
  static let agentLastError = "agentLastError"
  static let agentLastTick = "agentLastTick"
  static let agentPID = "agentPID"
  static let agentRegistrationFingerprint = "agentRegistrationFingerprint"
  static let agentSnapshot = "agentSnapshot"
  static let applyInBackground = "applyInBackground"
  static let boostEnabled = "boostEnabled"
  static let cpuLoadAssistCurvePoints = "cpuLoadAssistCurvePoints"
  static let cpuLoadAssistEnabled = "cpuLoadAssistEnabled"
  static let curveActive = "curveActive"
  static let curveNormalPriority = "curveNormalPriority"
  static let curvePoints = "curvePoints"
  static let extendedRangeConfigurationAllowed = "extendedRangeConfigurationAllowed"
  static let fanResponseValue = "fanResponseValue"
  static let gpuLoadAssistCurvePoints = "gpuLoadAssistCurvePoints"
  static let gpuLoadAssistEnabled = "gpuLoadAssistEnabled"
  static let gpuLoadFloorThreshold = "gpuLoadFloorThreshold"
  static let inferFanResponseFromGraph = "inferFanResponseFromGraph"
  static let interpolationMode = "interpolationMode"
  static let loadAssistMigrationVersion = "loadAssistMigrationVersion"
  static let loadFloorEnabled = "loadFloorEnabled"
  static let loadFloorThreshold = "loadFloorThreshold"
  static let overdriveEnabled = "overdriveEnabled"
  static let overdriveTargetRPMMeasured = "overdriveTargetRPMMeasured"
  static let systemHelperReplacementPending = "systemHelperReplacementPending"
  static let underdriveEnabled = "underdriveEnabled"
  static let userBoostPriority = "userBoostPriority"
}
