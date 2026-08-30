//
//  AgentController+SensorResolution.swift
//  FanCurveAgent
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

let sensorResolutionLog = AppLog.make(category: "AgentSensorResolution")

extension AgentController {
  /// Resolves the effective SMC temperature key set once per process
  /// lifetime, against the keys the SMC actually reports rather than the
  /// `hw.model` catalog guess. Runs inline as the first step of `tick()` so
  /// it shares the tick loop's single-in-flight serialization and never
  /// races the other mutations `tick()` makes to controller state.
  func resolveSensorKeysIfNeeded() async {
    guard !sensorKeysResolved else { return }
    sensorKeysResolved = true

    sensorResolutionLog.notice(
      "agent.sensor_resolution.started catalogCount=\(Self.catalogTempKeys.count, privacy: .public)"
    )

    let resolved = await SensorKeyResolver.resolve(
      catalogTempKeys: Self.catalogTempKeys,
      catalogCPUTempKeys: Self.catalogCPUTempKeys,
      discoverer: fanHardware
    )

    tempKeys = resolved.tempKeys
    cpuTempKeys = resolved.cpuTempKeys

    // Counts and the decision only. `SensorKeyResolver` already logs the key
    // lists themselves, capped, so repeating them here would double the noise.
    sensorResolutionLog.notice(
      "agent.sensor_resolution.completed resolvedCount=\(resolved.tempKeys.count, privacy: .public) excludedCount=\(resolved.excludedKeys.count, privacy: .public) usedFallback=\(resolved.usedFallback, privacy: .public) reason=\(resolved.fallbackReason?.description ?? "none", privacy: .public)"
    )
  }
}
