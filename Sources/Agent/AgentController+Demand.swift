//
//  AgentController+Demand.swift
//  FanCurveAgent
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

import Foundation

private enum DemandConstants {
  // Controller mode tolerance: observed vs committed percent band that determines ramp direction
  static let controllerModeTolerance: Double = 0.006

  // dt clamping bounds for conditioning time step
  static let dtMinSeconds: Double = 0.001
  static let dtMaxSeconds: Double = 5.0

  // Acceleration-limited convergence threshold: treat as reached when residual is below this
  static let convergenceThreshold: Double = 0.0001

  // Kinematic stopping-velocity coefficient: v = sqrt(2 * a * distance)
  static let stoppingVelocityCoefficient: Double = 2

  // Thermal debt: comfort-over-temp parameters (slow temp above which heat contribution begins)
  static let comfortOverTempBaselineC: Double = 58.0
  static let comfortOverTempRangeC: Double = 22.0

  // Thermal debt: rise pressure parameters (fast-minus-slow delta threshold and normalizer)
  static let risePressureDeltaThresholdC: Double = 0.25
  static let risePressureNormalizerC: Double = 3.0

  // Thermal debt: fast trend pressure parameters (trend threshold and gain factor)
  static let fastTrendPressureThreshold: Double = 0.04
  static let fastTrendPressureGain: Double = 2.8

  // Thermal debt: sustained load pressure parameters (load threshold, normalizer, and weight)
  static let sustainedLoadThresholdPercent: Double = 45.0
  static let sustainedLoadNormalizerPercent: Double = 55.0
  static let sustainedLoadWeight: Double = 0.35

  // Thermal debt: band escalation contribution when fan stepped up
  static let bandEscalationPressure: Double = 0.06

  // Thermal debt: stable-cooling detection thresholds
  static let stableCoolingFastTrendMax: Double = 0.01
  static let stableCoolingSlowTrendMax: Double = -0.02
  static let stableCoolingBaselineTolerance: Double = 0.001

  // Thermal debt: low-load detection threshold and pressure contribution
  static let lowLoadThresholdPercent: Double = 25.0
  static let lowLoadPressureContribution: Double = 0.4

  // Thermal debt: cool-temperature detection thresholds and pressure contribution
  static let coolTempSlowThresholdC: Double = 52.0
  static let coolTempRawThresholdC: Double = 55.0
  static let coolTempPressureContribution: Double = 0.35
}

extension AgentController {
  func bandControlledState(
    input: AgentControllerDemandTypes.BandControlInput
  ) -> AgentControllerDemandTypes.RuntimeBandState {
    let fastTrend = previousFastTemperature.map { input.fastTemperatureC - $0 } ?? 0
    let slowTrend = previousSlowTemperature.map { input.slowTemperatureC - $0 } ?? 0
    let baselinePercent = max(0, min(1, input.rawBaselinePercent))
    let committedPercent = max(0, min(1, input.conditionedDemandPercent))
    let observedPercent = input.observedFanPercent ?? committedPercent

    if observedPercent < committedPercent - DemandConstants.controllerModeTolerance {
      controllerMode = .rampingUp
    } else if observedPercent > committedPercent + DemandConstants.controllerModeTolerance {
      controllerMode = .rampingDown
    } else {
      controllerMode = .holding
    }

    updateThermalDebt(
      input: AgentControllerDemandTypes.ThermalDebtInput(
        rawTemperatureC: input.rawTemperatureC,
        fastTemperatureC: input.fastTemperatureC,
        slowTemperatureC: input.slowTemperatureC,
        fastTrend: fastTrend,
        slowTrend: slowTrend,
        cpuLoad: input.cpuLoad,
        rawBaselinePercent: input.rawBaselinePercent,
        committedPercent: committedPercent,
        steppedUp: observedPercent < committedPercent
      )
    )

    return AgentControllerDemandTypes.RuntimeBandState(
      committedPercent: committedPercent,
      commandedTargetTemperatureC: input.conditionedDemandTemperatureC,
      bandIndex: bandIndex(for: committedPercent),
      committedTemperatureC: input.slowTemperatureC,
      baseCurvePercent: input.baseCurvePercent,
      rawBaselinePercent: baselinePercent,
      semanticDemandPercent: baselinePercent,
      thermalDemandSource: input.demandSource,
      semanticDemandTemperatureC: input.semanticDemandTemperatureC,
      mode: controllerMode,
      holdRemainingSeconds: 0
    )
  }

  func observedCurvePercent(fans: [FanInfo]) -> Double? {
    let percents = fans.compactMap { fan -> Double? in
      guard fan.maxRPM > fan.minRPM, fan.actualRPM > 0 else { return nil }
      let percent = Double((fan.actualRPM - fan.minRPM) / (fan.maxRPM - fan.minRPM))
      return max(0, min(1, percent))
    }
    guard !percents.isEmpty else { return nil }
    return percents.reduce(0, +) / Double(percents.count)
  }

  func bandIndex(for percent: Double) -> Int {
    let clamped = max(0, min(1, percent))
    guard clamped > 0 else { return 0 }
    let bands = Int((1.0 / runtimeBandSize).rounded())
    return min(bands, Int(ceil(clamped / runtimeBandSize)))
  }

  func thermalPressureTemperature(fastTemperatureC: Double, slowTemperatureC: Double) -> Double {
    let fastTrend = previousFastTemperature.map { fastTemperatureC - $0 } ?? 0
    let trendLead = max(0, min(maximumThermalLeadC, fastTrend * thermalLeadSeconds))
    let ledTemperature = fastTemperatureC + trendLead
    return max(slowTemperatureC, ledTemperature)
  }

  func conditionedThermalDemand(
    rawPercent: Double,
    rawTemperatureC: Double,
    now: Date
  ) -> (percent: Double, temperatureC: Double) {
    let targetPercent = max(0, min(1, rawPercent))
    guard
      let currentPercent = conditionedDemandPercent,
      let currentTemperature = conditionedDemandTemperatureC,
      let lastTime = lastDemandConditioningTime
    else {
      conditionedDemandPercent = targetPercent
      conditionedDemandPercentVelocity = 0
      conditionedDemandTemperatureC = rawTemperatureC
      conditionedDemandTemperatureVelocityC = 0
      lastDemandConditioningTime = now
      return (targetPercent, rawTemperatureC)
    }

    let dt = max(
      DemandConstants.dtMinSeconds,
      min(DemandConstants.dtMaxSeconds, now.timeIntervalSince(lastTime)))
    let maxPercentVelocity =
      targetPercent >= currentPercent
      ? demandNormalRiseVelocityPerSecond
      : demandNormalFallVelocityPerSecond
    let nextPercent = accelerationLimitedStep(
      input: AgentControllerDemandTypes.AccelerationStepInput(
        current: currentPercent,
        target: targetPercent,
        velocity: conditionedDemandPercentVelocity,
        maxVelocity: maxPercentVelocity,
        maxAcceleration: demandNormalAccelerationPerSecond,
        elapsedSeconds: dt
      )
    )

    let maxTemperatureVelocity =
      rawTemperatureC >= currentTemperature
      ? demandTemperatureRiseVelocityCPerSecond
      : demandTemperatureFallVelocityCPerSecond
    let nextTemperature = accelerationLimitedStep(
      input: AgentControllerDemandTypes.AccelerationStepInput(
        current: currentTemperature,
        target: rawTemperatureC,
        velocity: conditionedDemandTemperatureVelocityC,
        maxVelocity: maxTemperatureVelocity,
        maxAcceleration: demandTemperatureAccelerationCPerSecond,
        elapsedSeconds: dt
      )
    )

    conditionedDemandPercent = nextPercent.value
    conditionedDemandPercentVelocity = nextPercent.velocity
    conditionedDemandTemperatureC = nextTemperature.value
    conditionedDemandTemperatureVelocityC = nextTemperature.velocity
    lastDemandConditioningTime = now
    return (nextPercent.value, nextTemperature.value)
  }

  func accelerationLimitedStep(
    input: AgentControllerDemandTypes.AccelerationStepInput
  ) -> (value: Double, velocity: Double) {
    let delta = input.target - input.current
    guard delta != 0, input.elapsedSeconds > 0 else {
      return (input.target, 0)
    }

    let direction = delta > 0 ? 1.0 : -1.0
    let clampedMaxVelocity = max(0, input.maxVelocity)
    let clampedAcceleration = max(0, input.maxAcceleration)
    let stoppingVelocity = sqrt(
      DemandConstants.stoppingVelocityCoefficient * clampedAcceleration * abs(delta))
    let desiredVelocity = direction * min(clampedMaxVelocity, stoppingVelocity)
    let nextVelocity = limitedStep(
      current: input.velocity,
      target: desiredVelocity,
      maximumDelta: clampedAcceleration * input.elapsedSeconds
    )
    let nextValue = input.current + nextVelocity * input.elapsedSeconds

    let reachedTarget =
      (input.target - nextValue).sign != delta.sign
      || abs(input.target - nextValue) < DemandConstants.convergenceThreshold
    if reachedTarget {
      return (input.target, 0)
    }
    return (nextValue, nextVelocity)
  }

  func limitedStep(current: Double, target: Double, maximumDelta: Double) -> Double {
    let delta = target - current
    guard abs(delta) > maximumDelta else { return target }
    return current + maximumDelta * (delta > 0 ? 1 : -1)
  }

  func updateThermalDebt(input: AgentControllerDemandTypes.ThermalDebtInput) {
    let comfortOverTemp =
      max(0, input.slowTemperatureC - DemandConstants.comfortOverTempBaselineC)
      / DemandConstants.comfortOverTempRangeC
    let risePressure =
      max(
        0,
        input.fastTemperatureC - input.slowTemperatureC
          - DemandConstants.risePressureDeltaThresholdC)
      / DemandConstants.risePressureNormalizerC
    let fastTrendPressure =
      max(0, input.fastTrend - DemandConstants.fastTrendPressureThreshold)
      * DemandConstants.fastTrendPressureGain
    let sustainedLoadPressure =
      max(0, input.cpuLoad - DemandConstants.sustainedLoadThresholdPercent)
      / DemandConstants.sustainedLoadNormalizerPercent * DemandConstants.sustainedLoadWeight
    let bandEscalationPressure = input.steppedUp ? DemandConstants.bandEscalationPressure : 0.0

    let stableCooling =
      input.fastTrend <= DemandConstants.stableCoolingFastTrendMax
      && input.slowTrend <= DemandConstants.stableCoolingSlowTrendMax
      && input.rawBaselinePercent <= input.committedPercent
        + DemandConstants.stableCoolingBaselineTolerance
    let coolingPressure = stableCooling ? 1.0 : 0.0
    let lowLoadPressure =
      input.cpuLoad < DemandConstants.lowLoadThresholdPercent
      ? DemandConstants.lowLoadPressureContribution : 0.0
    let coolTempPressure =
      input.slowTemperatureC < DemandConstants.coolTempSlowThresholdC
        && input.rawTemperatureC < DemandConstants.coolTempRawThresholdC
      ? DemandConstants.coolTempPressureContribution : 0.0

    let heatContribution =
      comfortOverTemp
      + risePressure
      + fastTrendPressure
      + sustainedLoadPressure
      + bandEscalationPressure
    let coolingContribution = coolingPressure + lowLoadPressure + coolTempPressure

    thermalDebt = max(
      0,
      min(
        1,
        thermalDebt
          + thermalDebtRiseRatePerTick * heatContribution
          - thermalDebtFallRatePerTick * coolingContribution
      )
    )
  }
}
