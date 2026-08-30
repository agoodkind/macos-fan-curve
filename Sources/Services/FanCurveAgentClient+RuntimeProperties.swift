//
//  FanCurveAgentClient+RuntimeProperties.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - Runtime properties

extension FanCurveAgentClient {
  var isFresh: Bool {
    guard runtimeState.health.permitsFreshTelemetry else { return false }
    guard let snapshot else { return false }
    return Date().timeIntervalSince(snapshot.timestamp)
      < FanCurveAgentClientConstants.snapshotFreshnessWindow
  }

  var governingTemperature: Double { snapshot?.governingTemperatureC ?? 0 }
  var committedTemperature: Double { snapshot?.committedTemperatureC ?? 0 }
  var rawPressureTemperature: Double? { snapshot?.rawPressureTemperatureC }
  var fans: [AgentFanSnapshot] { snapshot?.fans ?? [] }
  var cpuLoadPercent: Double { snapshot?.cpuLoadPercent ?? 0 }
  var gpuLoadPercent: Double { snapshot?.gpuLoadPercent ?? 0 }
  var baseCurvePercent: Double { snapshot?.baseCurvePercent ?? 0 }
  var rawBaselinePercent: Double { snapshot?.rawBaselinePercent ?? 0 }
  var semanticDemandPercent: Double? { snapshot?.semanticDemandPercent }
  var semanticDemandTemperature: Double? { snapshot?.semanticDemandTemperatureC }
  var commandedTargetPercent: Double {
    snapshot?.commandedTargetPercent ?? snapshot?.committedPercent ?? 0
  }
  var assistFloorPercent: Double? { snapshot?.assistFloorPercent }
  var activeAssistKinds: [LoadAssistKind] { snapshot?.activeAssistKinds ?? [] }
  var helperReachable: Bool { snapshot?.helperReachable ?? false }
  var boostEnabled: Bool { snapshot?.boostEnabled ?? false }
  var curveActive: Bool { snapshot?.curveActive ?? false }
}
