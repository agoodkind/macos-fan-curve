//
//  FanResponse.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-11.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let fanResponseLog = AppLog.make(category: "FanResponse")

// MARK: - Constants

private enum FanResponseConstants {
  // Slope thresholds used to normalize curve steepness into a response value
  static let gentleSlopePercentPerC: Double = 0.002
  static let fastSlopePercentPerC: Double = 0.03

  // Ramp multiplier coefficients for below-balanced and above-balanced ranges
  static let rampLowBase: Double = 0.55
  static let rampLowFactor: Double = 0.45
  static let rampHighFactor: Double = 0.6

  // Bias multiplier coefficients for below-balanced and above-balanced ranges
  static let biasLowBase: Double = 0.75
  static let biasLowFactor: Double = 0.25
  static let biasHighFactor: Double = 0.25

  // Output clamp bounds applied to every FanResponseMultiplier
  static let multiplierMin: Double = 0.45
  static let multiplierMax: Double = 1.8
}

struct FanResponse: Sendable, Equatable {
  static let defaultValue: Double = 0.5
  static let defaultInferFromGraph = true

  let value: Double

  init(value: Double) {
    self.value = Self.clampedValue(value)
  }

  static var balanced: FanResponse {
    FanResponse(value: defaultValue)
  }

  var manualMultiplier: FanResponseMultiplier {
    FanResponseMultiplier(Self.rampMultiplier(for: value))
  }

  var biasMultiplier: FanResponseMultiplier {
    FanResponseMultiplier(Self.biasMultiplier(for: value))
  }

  static func loadValue(defaults: UserDefaults) -> FanResponse {
    guard defaults.object(forKey: SharedConfigKeys.fanResponseValue) != nil else {
      fanResponseLog.debug("fan_response.value.default recovery=balanced")
      return .balanced
    }
    return FanResponse(value: defaults.double(forKey: SharedConfigKeys.fanResponseValue))
  }

  static func loadInferFromGraph(defaults: UserDefaults) -> Bool {
    guard defaults.object(forKey: SharedConfigKeys.inferFanResponseFromGraph) != nil else {
      return defaultInferFromGraph
    }
    return defaults.bool(forKey: SharedConfigKeys.inferFanResponseFromGraph)
  }

  static func finalMultiplier(
    manualResponse: FanResponse,
    inferredResponse: FanResponse?,
    inferFromGraph: Bool
  ) -> FanResponseMultiplier {
    guard inferFromGraph, let inferredResponse else {
      return manualResponse.manualMultiplier
    }

    return FanResponseMultiplier(
      inferredResponse.manualMultiplier.rawValue * manualResponse.biasMultiplier.rawValue
    )
  }

  static func responseValue(forSlopePercentPerC slopePercentPerC: Double) -> FanResponse {
    let normalized =
      (abs(slopePercentPerC) - FanResponseConstants.gentleSlopePercentPerC)
      / (FanResponseConstants.fastSlopePercentPerC
        - FanResponseConstants.gentleSlopePercentPerC)
    return FanResponse(value: normalized)
  }

  private static func clampedValue(_ value: Double) -> Double {
    max(0, min(1, value))
  }

  private static func rampMultiplier(for value: Double) -> Double {
    let clampedValue = clampedValue(value)
    if clampedValue <= defaultValue {
      let progress = clampedValue / defaultValue
      return FanResponseConstants.rampLowBase + progress * FanResponseConstants.rampLowFactor
    }

    let progress = (clampedValue - defaultValue) / defaultValue
    return 1.0 + progress * FanResponseConstants.rampHighFactor
  }

  private static func biasMultiplier(for value: Double) -> Double {
    let clampedValue = clampedValue(value)
    if clampedValue <= defaultValue {
      let progress = clampedValue / defaultValue
      return FanResponseConstants.biasLowBase + progress * FanResponseConstants.biasLowFactor
    }

    let progress = (clampedValue - defaultValue) / defaultValue
    return 1.0 + progress * FanResponseConstants.biasHighFactor
  }
}

struct FanResponseMultiplier: Sendable, Equatable {
  let rawValue: Double

  init(_ rawValue: Double) {
    self.rawValue = max(
      FanResponseConstants.multiplierMin, min(FanResponseConstants.multiplierMax, rawValue))
  }
}
