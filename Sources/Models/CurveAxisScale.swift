//
//  CurveAxisScale.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-06-04.
//  Copyright © 2026, all rights reserved.
//

import Foundation

private enum CurveAxisScaleConstants {
  static let minimumFraction: Double = 0
  static let maximumFraction: Double = 1
}

// MARK: - CurveAxisScale

enum CurveAxisScale: Sendable {
  case fanTemperature(TemperatureAxisScale)
  case linear(range: ClosedRange<Double>)

  static let fanCurveDefault = CurveAxisScale.fanTemperature(.fanCurveDefault)

  var range: ClosedRange<Double> {
    switch self {
    case .fanTemperature(let scale):
      return scale.temperatureRangeC
    case .linear(let range):
      return range
    }
  }

  func fraction(for value: Double) -> Double {
    switch self {
    case .fanTemperature(let scale):
      return scale.fraction(for: value)
    case .linear(let range):
      let clampedValue = max(range.lowerBound, min(range.upperBound, value))
      let width = range.upperBound - range.lowerBound
      guard width > 0 else { return CurveAxisScaleConstants.minimumFraction }
      return (clampedValue - range.lowerBound) / width
    }
  }

  func value(at fraction: Double) -> Double {
    let clampedFraction = max(
      CurveAxisScaleConstants.minimumFraction,
      min(CurveAxisScaleConstants.maximumFraction, fraction)
    )

    switch self {
    case .fanTemperature(let scale):
      return scale.temperatureC(at: clampedFraction)
    case .linear(let range):
      let width = range.upperBound - range.lowerBound
      return range.lowerBound + (clampedFraction * width)
    }
  }
}
