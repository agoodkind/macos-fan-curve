//
//  AgentController+SensorResolution.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import Foundation

extension AgentController {
  /// Resolves the effective SMC temperature key set once per process
  /// lifetime, against the keys the SMC actually reports rather than the
  /// `hw.model` catalog guess. Runs inline as the first step of `tick()` so
  /// it shares the tick loop's single-in-flight serialization and never
  /// races the other mutations `tick()` makes to controller state.
  func resolveSensorKeysIfNeeded() async {
    guard !sensorKeysResolved else { return }
    sensorKeysResolved = true

    let resolved = await SensorKeyResolver.resolve(
      catalogTempKeys: Self.catalogTempKeys,
      catalogCPUTempKeys: Self.catalogCPUTempKeys,
      discoverer: fanHardware
    )

    tempKeys = resolved.tempKeys
    cpuTempKeys = resolved.cpuTempKeys
  }
}
