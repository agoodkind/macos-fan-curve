//
//  LiveMarkerPresentation.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-01.
//  Copyright © 2026, all rights reserved.
//

import Foundation

enum LiveMarkerPresentation {
  struct Values: Sendable, Equatable {
    var fanTemperatureC: Double
    var fanPercent: Double
    var demandTemperatureC: Double
    var demandPercent: Double
    var demandBasePercent: Double
  }

  struct Target: Sendable, Equatable {
    var values: Values
    var generation: Generation

    struct Generation: Sendable, Equatable {
      var curveActive: Bool
      var boostEnabled: Bool
      var fanSignature: String
      var rpmRangeMin: Float
      var rpmRangeMax: Float
    }
  }

  struct TargetInput: Sendable {
    var curveActive: Bool
    var boostEnabled: Bool
    var governingTemperatureC: Double
    var committedTemperatureC: Double
    var rawPressureTemperatureC: Double?
    var semanticDemandTemperatureC: Double?
    var baseCurvePercent: Double?
    var semanticDemandPercent: Double?
    var commandedTargetPercent: Double
    var rawBaselinePercent: Double
    var fans: [AgentFanSnapshot]
    var rpmRange: (min: Float, max: Float)
    var previewPercent: Double
    var fanTemperatureC: Double?
  }

  static func presentDemandPercent(
    currentPercent: Double,
    proposedPercent: Double,
    alpha: Double,
    maximumStep: Double
  ) -> Double {
    guard proposedPercent < currentPercent else { return proposedPercent }

    let delta = proposedPercent - currentPercent
    let easedStep = delta * max(0, min(1, alpha))
    let clampedStep = max(-maximumStep, min(maximumStep, easedStep))
    return currentPercent + clampedStep
  }

  static func makeTarget(from input: TargetInput) -> Target? {
    let liveTemperature =
      input.semanticDemandTemperatureC
      ?? input.rawPressureTemperatureC
      ?? (input.committedTemperatureC > 0
        ? input.committedTemperatureC : input.governingTemperatureC)
    guard liveTemperature > 0 else { return nil }

    let fanPercent =
      actualFanPercent(fans: input.fans, rpmRange: input.rpmRange)
      ?? (input.curveActive ? input.commandedTargetPercent : input.previewPercent)
    let fanTemperature = input.fanTemperatureC ?? liveTemperature
    let demandPercent =
      input.curveActive
      ? clampedPercent(input.semanticDemandPercent ?? input.rawBaselinePercent)
      : input.previewPercent
    let basePercent = clampedPercent(input.baseCurvePercent ?? input.previewPercent)

    return Target(
      values: Values(
        fanTemperatureC: fanTemperature,
        fanPercent: clampedPercent(fanPercent),
        demandTemperatureC: liveTemperature,
        demandPercent: demandPercent,
        demandBasePercent: basePercent
      ),
      generation: Target.Generation(
        curveActive: input.curveActive,
        boostEnabled: input.boostEnabled,
        fanSignature: fanSignature(input.fans),
        rpmRangeMin: input.rpmRange.min,
        rpmRangeMax: input.rpmRange.max
      )
    )
  }

  private static func actualFanPercent(
    fans: [AgentFanSnapshot],
    rpmRange: (min: Float, max: Float)
  ) -> Double? {
    guard rpmRange.max > rpmRange.min else { return nil }
    let percents = fans.compactMap { fan -> Double? in
      guard fan.actualRPM >= 0 else { return nil }
      let percent = Double((fan.actualRPM - rpmRange.min) / (rpmRange.max - rpmRange.min))
      return clampedPercent(percent)
    }
    guard !percents.isEmpty else { return nil }
    return percents.reduce(0, +) / Double(percents.count)
  }

  private static func fanSignature(_ fans: [AgentFanSnapshot]) -> String {
    fans.map { "\($0.index):\(Int($0.minRPM)):\(Int($0.maxRPM))" }.joined(separator: "|")
  }

  private static func clampedPercent(_ percent: Double) -> Double {
    max(0, min(1, percent))
  }
}
