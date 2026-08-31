//
//  AcousticRampGovernor.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-30.
//  Copyright © 2026, all rights reserved.
//

import Foundation

private enum AcousticRampGovernorConstants {
  static let defaultQuietRiseRPMPerSecond: Float = 16
  static let defaultWarmRiseRPMPerSecond: Float = 24
  static let defaultHotRiseRPMPerSecond: Float = 38
  static let defaultQuietFallRPMPerSecond: Float = 18
  static let defaultThermalDebtMinFallRPMPerSecond: Float = 8
  static let defaultWarmTemperatureC: Double = 80
  static let defaultHotTemperatureC: Double = 86
  static let defaultRisingFastTrendCPerTick: Double = 0.14
  static let defaultRisingSlowTrendCPerTick: Double = 0.06
  static let defaultMinimumSnapRPMDelta: Float = 35
  static let maxElapsedSeconds: TimeInterval = 10
}

struct AcousticRampGovernor: Sendable {
  struct Policy: Sendable {
    let quietRiseRPMPerSecond: Float
    let warmRiseRPMPerSecond: Float
    let hotRiseRPMPerSecond: Float
    let quietFallRPMPerSecond: Float
    let thermalDebtMinimumFallRPMPerSecond: Float
    let warmTemperatureC: Double
    let hotTemperatureC: Double
    let risingFastTrendCPerTick: Double
    let risingSlowTrendCPerTick: Double
    let minimumSnapRPMDelta: Float

    static let fanCurveDefault = Policy(
      quietRiseRPMPerSecond: AcousticRampGovernorConstants.defaultQuietRiseRPMPerSecond,
      warmRiseRPMPerSecond: AcousticRampGovernorConstants.defaultWarmRiseRPMPerSecond,
      hotRiseRPMPerSecond: AcousticRampGovernorConstants.defaultHotRiseRPMPerSecond,
      quietFallRPMPerSecond: AcousticRampGovernorConstants.defaultQuietFallRPMPerSecond,
      thermalDebtMinimumFallRPMPerSecond: AcousticRampGovernorConstants
        .defaultThermalDebtMinFallRPMPerSecond,
      warmTemperatureC: AcousticRampGovernorConstants.defaultWarmTemperatureC,
      hotTemperatureC: AcousticRampGovernorConstants.defaultHotTemperatureC,
      risingFastTrendCPerTick: AcousticRampGovernorConstants.defaultRisingFastTrendCPerTick,
      risingSlowTrendCPerTick: AcousticRampGovernorConstants.defaultRisingSlowTrendCPerTick,
      minimumSnapRPMDelta: AcousticRampGovernorConstants.defaultMinimumSnapRPMDelta)

    func scalingRPMRates(by responseMultiplier: FanResponseMultiplier) -> Policy {
      let multiplier = Float(responseMultiplier.rawValue)
      return Policy(
        quietRiseRPMPerSecond: quietRiseRPMPerSecond * multiplier,
        warmRiseRPMPerSecond: warmRiseRPMPerSecond * multiplier,
        hotRiseRPMPerSecond: hotRiseRPMPerSecond * multiplier,
        quietFallRPMPerSecond: quietFallRPMPerSecond * multiplier,
        thermalDebtMinimumFallRPMPerSecond: thermalDebtMinimumFallRPMPerSecond * multiplier,
        warmTemperatureC: warmTemperatureC,
        hotTemperatureC: hotTemperatureC,
        risingFastTrendCPerTick: risingFastTrendCPerTick,
        risingSlowTrendCPerTick: risingSlowTrendCPerTick,
        minimumSnapRPMDelta: minimumSnapRPMDelta)
    }
  }

  struct Input: Sendable {
    let requestedRPM: Float
    let baselineRPM: Float
    let elapsedSeconds: TimeInterval
    let currentTemperatureC: Double
    let fastTrendCPerTick: Double
    let slowTrendCPerTick: Double
    let thermalDebt: Double
  }

  struct Decision: Sendable, Equatable {
    let requestedRPM: Float
    let commandedRPM: Float
    let baselineRPM: Float
    let elapsedSeconds: TimeInterval
    let rateRPMPerSecond: Float
    let limited: Bool
  }

  let policy: Policy

  init(policy: Policy = .fanCurveDefault) {
    self.policy = policy
  }

  func decision(for input: Input, policy effectivePolicy: Policy? = nil) -> Decision {
    let activePolicy = effectivePolicy ?? policy
    let delta = input.requestedRPM - input.baselineRPM
    guard delta != 0 else {
      return Decision(
        requestedRPM: input.requestedRPM,
        commandedRPM: input.requestedRPM,
        baselineRPM: input.baselineRPM,
        elapsedSeconds: normalizedElapsedSeconds(input.elapsedSeconds),
        rateRPMPerSecond: 0,
        limited: false)
    }

    let elapsedSeconds = normalizedElapsedSeconds(input.elapsedSeconds)
    let rateRPMPerSecond = selectedRateRPMPerSecond(
      input: input, delta: delta, policy: activePolicy)
    let allowedDelta = rateRPMPerSecond * Float(elapsedSeconds)
    let candidateRPM: Float
    if delta > 0 {
      candidateRPM = input.baselineRPM + min(delta, allowedDelta)
    } else {
      candidateRPM = input.baselineRPM + max(delta, -allowedDelta)
    }
    let commandedRPM = snappedCommandRPM(
      requestedRPM: input.requestedRPM,
      candidateRPM: max(0, candidateRPM),
      delta: delta)

    return Decision(
      requestedRPM: input.requestedRPM,
      commandedRPM: commandedRPM,
      baselineRPM: input.baselineRPM,
      elapsedSeconds: elapsedSeconds,
      rateRPMPerSecond: rateRPMPerSecond,
      limited: commandedRPM != input.requestedRPM)
  }

  private func selectedRateRPMPerSecond(input: Input, delta: Float, policy: Policy) -> Float {
    if delta > 0 {
      return selectedRiseRateRPMPerSecond(input: input, policy: policy)
    }

    let thermalDebt = max(0, min(1, input.thermalDebt))
    return policy.quietFallRPMPerSecond
      - Float(thermalDebt)
      * (policy.quietFallRPMPerSecond - policy.thermalDebtMinimumFallRPMPerSecond)
  }

  private func selectedRiseRateRPMPerSecond(input: Input, policy: Policy) -> Float {
    let thermalDebt = max(0, min(1, input.thermalDebt))
    let thermalDebtRate =
      policy.quietRiseRPMPerSecond
      + Float(thermalDebt) * (policy.hotRiseRPMPerSecond - policy.quietRiseRPMPerSecond)
    let isTemperatureRising =
      input.fastTrendCPerTick >= policy.risingFastTrendCPerTick
      || input.slowTrendCPerTick >= policy.risingSlowTrendCPerTick
    let trendRate: Float
    if isTemperatureRising {
      trendRate = policy.warmRiseRPMPerSecond
    } else {
      trendRate = policy.quietRiseRPMPerSecond
    }
    let temperatureRate: Float
    if input.currentTemperatureC >= policy.hotTemperatureC {
      temperatureRate = policy.hotRiseRPMPerSecond
    } else if input.currentTemperatureC >= policy.warmTemperatureC {
      temperatureRate = policy.warmRiseRPMPerSecond
    } else {
      temperatureRate = policy.quietRiseRPMPerSecond
    }

    return max(thermalDebtRate, trendRate, temperatureRate)
  }

  private func snappedCommandRPM(
    requestedRPM: Float,
    candidateRPM: Float,
    delta: Float
  ) -> Float {
    guard abs(delta) > policy.minimumSnapRPMDelta else {
      return requestedRPM
    }
    if delta > 0 {
      return min(requestedRPM, candidateRPM)
    }
    return max(requestedRPM, candidateRPM)
  }

  private func normalizedElapsedSeconds(_ elapsedSeconds: TimeInterval) -> TimeInterval {
    max(0, min(AcousticRampGovernorConstants.maxElapsedSeconds, elapsedSeconds))
  }
}
