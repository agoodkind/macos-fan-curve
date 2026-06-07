//
//  TemperatureAxisScale.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-01.
//  Copyright © 2026, all rights reserved.
//

import Foundation

private enum TemperatureAxisScaleConstants {
  // Default fan curve control-point temperatures (°C), defining the compressed axis layout.
  static let controlPointTempC0: Double = 35
  static let controlPointTempC1: Double = 78
  static let controlPointTempC2: Double = 84
  static let controlPointTempC3: Double = 90
  static let controlPointTempC4: Double = 96
  static let controlPointTempC5: Double = 101
  static let controlPointTempC6: Double = 106
  static let controlPointTempC7: Double = 110
  static let defaultControlPointTemperaturesC: [Double] = [
    controlPointTempC0,
    controlPointTempC1,
    controlPointTempC2,
    controlPointTempC3,
    controlPointTempC4,
    controlPointTempC5,
    controlPointTempC6,
    controlPointTempC7,
  ]
  static let defaultMinorTickStepC: Double = 2.5
  static let defaultMajorTickStepC: Double = 10

  // Fallback axis bounds used when fewer than two valid control points are supplied.
  static let fallbackMinTempC: Double = 20
  static let fallbackMaxTempC: Double = 120

  // Minimum safe tick step to prevent an infinite tick-generation loop.
  static let minimumTickStepC: Double = 1

  // Minimum control points needed to define an axis with at least one interpolation segment.
  static let minimumControlPointCount: Int = 2

  // Offset from count to the last segment's lower index (count - 2 is the last left point).
  static let lastSegmentLowerIndexOffset: Int = 2
}

struct TemperatureAxisScale: Sendable {
  static let fanCurveDefault = TemperatureAxisScale(
    controlPointTemperaturesC: TemperatureAxisScaleConstants.defaultControlPointTemperaturesC,
    minorTickStepC: TemperatureAxisScaleConstants.defaultMinorTickStepC,
    majorTickStepC: TemperatureAxisScaleConstants.defaultMajorTickStepC
  )

  let temperatureRangeC: ClosedRange<Double>
  let controlPointTemperaturesC: [Double]
  let minorTickTemperaturesC: [Double]
  let majorTickTemperaturesC: [Double]

  init(
    controlPointTemperaturesC: [Double],
    minorTickStepC: Double,
    majorTickStepC: Double
  ) {
    let safeControlPointTemperatures = Self.sanitizedControlPointTemperatures(
      controlPointTemperaturesC
    )
    let safeTemperatureRange =
      safeControlPointTemperatures[
        0]...safeControlPointTemperatures[safeControlPointTemperatures.count - 1]
    self.temperatureRangeC = safeTemperatureRange
    self.controlPointTemperaturesC = safeControlPointTemperatures
    self.minorTickTemperaturesC = Self.intervalTicks(
      in: safeTemperatureRange,
      stepC: minorTickStepC
    )
    self.majorTickTemperaturesC = Self.intervalTicks(
      in: safeTemperatureRange,
      stepC: majorTickStepC
    )
  }

  func fraction(for temperatureC: Double) -> Double {
    let clampedTemperature = max(
      temperatureRangeC.lowerBound, min(temperatureRangeC.upperBound, temperatureC))
    guard let firstTemperature = controlPointTemperaturesC.first else { return 0 }
    guard let lastTemperature = controlPointTemperaturesC.last else { return 0 }

    if clampedTemperature <= firstTemperature { return 0 }
    if clampedTemperature >= lastTemperature { return 1 }

    for pointIndex in 0..<(controlPointTemperaturesC.count - 1) {
      let leftTemperature = controlPointTemperaturesC[pointIndex]
      let rightTemperature = controlPointTemperaturesC[pointIndex + 1]
      if clampedTemperature >= leftTemperature, clampedTemperature <= rightTemperature {
        return fraction(
          temperatureC: clampedTemperature,
          pointIndex: pointIndex,
          leftTemperature: leftTemperature,
          rightTemperature: rightTemperature
        )
      }
    }

    return 1
  }

  func temperatureC(at fraction: Double) -> Double {
    let clampedFraction = max(0, min(1, fraction))
    guard clampedFraction > 0 else { return temperatureRangeC.lowerBound }
    guard clampedFraction < 1 else { return temperatureRangeC.upperBound }
    let scaledFraction = clampedFraction * Double(controlPointTemperaturesC.count - 1)
    let pointIndex = min(
      controlPointTemperaturesC.count
        - TemperatureAxisScaleConstants.lastSegmentLowerIndexOffset,
      max(0, Int(scaledFraction.rounded(.down)))
    )
    let localFraction = scaledFraction - Double(pointIndex)
    return Self.interpolate(
      lowerBound: controlPointTemperaturesC[pointIndex],
      upperBound: controlPointTemperaturesC[pointIndex + 1],
      progress: localFraction
    )
  }

  private static func intervalTicks(
    in temperatureRangeC: ClosedRange<Double>,
    stepC: Double
  ) -> [Double] {
    let safeStep = max(TemperatureAxisScaleConstants.minimumTickStepC, stepC)
    var ticks = [temperatureRangeC.lowerBound]
    var nextTick = ceil(temperatureRangeC.lowerBound / safeStep) * safeStep
    if nextTick <= temperatureRangeC.lowerBound {
      nextTick += safeStep
    }
    while nextTick < temperatureRangeC.upperBound {
      ticks.append(nextTick)
      nextTick += safeStep
    }
    if ticks.last != temperatureRangeC.upperBound {
      ticks.append(temperatureRangeC.upperBound)
    }
    return ticks
  }

  private static func sanitizedControlPointTemperatures(_ temperatures: [Double]) -> [Double] {
    let sortedTemperatures = temperatures.sorted()
    guard sortedTemperatures.count >= TemperatureAxisScaleConstants.minimumControlPointCount
    else {
      return [
        TemperatureAxisScaleConstants.fallbackMinTempC,
        TemperatureAxisScaleConstants.fallbackMaxTempC,
      ]
    }
    return sortedTemperatures
  }

  private static func interpolate(
    lowerBound: Double,
    upperBound: Double,
    progress: Double
  ) -> Double {
    lowerBound + max(0, min(1, progress)) * (upperBound - lowerBound)
  }

  private func fraction(
    temperatureC: Double,
    pointIndex: Int,
    leftTemperature: Double,
    rightTemperature: Double
  ) -> Double {
    let leftFraction = Double(pointIndex) / Double(controlPointTemperaturesC.count - 1)
    let rightFraction = Double(pointIndex + 1) / Double(controlPointTemperaturesC.count - 1)
    let localFraction =
      (temperatureC - leftTemperature) / (rightTemperature - leftTemperature)
    return Self.interpolate(
      lowerBound: leftFraction, upperBound: rightFraction, progress: localFraction)
  }
}
