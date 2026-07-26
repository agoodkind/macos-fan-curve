//
//  AgentControllerTickTypes.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

import Foundation

enum AgentControllerTickTypes {
  struct TickTelemetry {
    let active: Bool
    let result: FanHardwareBatchRead
    let transitioned: Bool
    let maxCPUTemp: Double
    let cpuLoad: Double
    let gpuLoad: Double
  }

  struct AssistState {
    let rawBaselinePercent: Double
    let assistFloorPercent: Double?
    let assistAppliedKinds: [LoadAssistKind]
    let demandSource: ThermalDemandSource
  }

  struct ActiveTickContext {
    let telemetry: TickTelemetry
    let now: Date
    let fastTemp: Double
    let slowTemp: Double
    let fastTrend: Double
    let slowTrend: Double
    let boost: Bool
    let pressureTemperature: Double
    let baseCurvePercent: Double
    let fanResponseMultiplier: FanResponseMultiplier
    let fanResponseInferred: Bool
    let rawBaselinePercent: Double
    let assistFloorPercent: Double?
    let assistAppliedKinds: [LoadAssistKind]
    let demandSource: ThermalDemandSource
    let conditionedDemand: (percent: Double, temperatureC: Double)
  }

  struct FanActions {
    let setFans: [(index: UInt, rpm: Float)]
    let autoFans: [UInt]
    let tickPriority: Int
    let assistSummary: String
  }
}
