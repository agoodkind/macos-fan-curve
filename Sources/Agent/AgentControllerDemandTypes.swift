//
//  AgentControllerDemandTypes.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

import Foundation

enum AgentControllerDemandTypes {
  struct RuntimeBandState {
    let committedPercent: Double
    let commandedTargetTemperatureC: Double?
    let bandIndex: Int
    let committedTemperatureC: Double
    let baseCurvePercent: Double
    let rawBaselinePercent: Double
    let semanticDemandPercent: Double
    let thermalDemandSource: ThermalDemandSource
    let semanticDemandTemperatureC: Double?
    let mode: AgentControllerMode
    let holdRemainingSeconds: Double
  }

  struct BandControlInput {
    let rawBaselinePercent: Double
    let semanticDemandTemperatureC: Double
    let conditionedDemandPercent: Double
    let conditionedDemandTemperatureC: Double
    let baseCurvePercent: Double
    let demandSource: ThermalDemandSource
    let rawTemperatureC: Double
    let fastTemperatureC: Double
    let slowTemperatureC: Double
    let cpuLoad: Double
    let observedFanPercent: Double?
  }

  struct ThermalDebtInput {
    let rawTemperatureC: Double
    let fastTemperatureC: Double
    let slowTemperatureC: Double
    let fastTrend: Double
    let slowTrend: Double
    let cpuLoad: Double
    let rawBaselinePercent: Double
    let committedPercent: Double
    let steppedUp: Bool
  }

  struct AccelerationStepInput {
    let current: Double
    let target: Double
    let velocity: Double
    let maxVelocity: Double
    let maxAcceleration: Double
    let elapsedSeconds: Double
  }
}
