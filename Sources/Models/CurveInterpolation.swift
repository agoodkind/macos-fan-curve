//
//  CurveInterpolation.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026, all rights reserved.
//

import Foundation

private enum CurveInterpolationConstants {
  /// Radius (in °C) used when numerically estimating the local slope.
  static let sampleRadiusC: Double = 1.0
  /// Fallback radius multiplier when the primary window collapses.
  static let sampleRadiusExpandFactor: Double = 2.0
  /// Minimum absolute denominator below which a division is considered degenerate.
  static let divisionEpsilon: Double = 0.000001
  /// Tolerance for treating two temperature values as coincident with an axis endpoint.
  static let axisSnapTolerance: Double = 0.001
  /// Default number of path-point steps used when rendering the curve.
  static let defaultPathSteps: Int = 100
  // Hermite basis / weight coefficients (standard cubic Hermite polynomial).
  static let hermiteCoeff2: Double = 2.0
  static let hermiteCoeff3: Double = 3.0
  /// Minimum control-point count needed to build any tangent (a single segment).
  static let minTangentPoints: Int = 2
  /// Control-point count below which the interior three-point stencil is unavailable.
  static let minInteriorStencilPoints: Int = 2
  /// Offset to the second neighbor used by the endpoint tangent three-point stencil.
  static let endpointSecondNeighborOffset: Int = 2
  /// Offset to the third neighbor used by the endpoint tangent three-point stencil.
  static let endpointThirdNeighborOffset: Int = 3
}

// MARK: - CurveInterpolationAxisHelpers

private enum CurveInterpolationAxisHelpers {
  static func resolvedAxisScale(
    points: [CurvePoint],
    preferredAxisScale: CurveAxisScale?
  ) -> CurveAxisScale? {
    if let preferredAxisScale {
      return preferredAxisScale
    }

    let defaultScale = CurveAxisScale.fanCurveDefault
    let range = defaultScale.range
    let sorted = points.sorted { $0.temperature < $1.temperature }

    guard
      let firstPoint = sorted.first,
      let lastPoint = sorted.last,
      abs(firstPoint.temperature - range.lowerBound)
        < CurveInterpolationConstants.axisSnapTolerance,
      abs(lastPoint.temperature - range.upperBound)
        < CurveInterpolationConstants.axisSnapTolerance
    else { return nil }

    return defaultScale
  }

  static func pathTemperature(
    at fraction: Double,
    in tempRange: ClosedRange<Double>,
    mode: InterpolationMode,
    axisScale: CurveAxisScale?
  ) -> Double {
    if mode == .catmullRom, let axisScale {
      return axisScale.value(at: fraction)
    }

    return tempRange.lowerBound + fraction * (tempRange.upperBound - tempRange.lowerBound)
  }
}

enum CurveInterpolation {
  private struct HermiteSegment {
    let currentFraction: Double
    let leftFraction: Double
    let rightFraction: Double
    let leftPercent: Double
    let rightPercent: Double
    let leftTangent: Double
    let rightTangent: Double
  }

  static func evaluate(
    at temperature: Double,
    points: [CurvePoint],
    mode: InterpolationMode,
    axisScale: CurveAxisScale? = nil
  ) -> Double {
    switch mode {
    case .linear: return linear(at: temperature, points: points)
    case .catmullRom:
      return catmullRom(at: temperature, points: points, axisScale: axisScale)
    }
  }

  static func localResponse(
    at temperature: Double,
    points: [CurvePoint],
    mode: InterpolationMode,
    axisScale: CurveAxisScale? = nil
  ) -> FanResponse {
    FanResponse.responseValue(
      forSlopePercentPerC: localSlopePercentPerC(
        at: temperature,
        points: points,
        mode: mode,
        axisScale: axisScale
      )
    )
  }

  static func localSlopePercentPerC(
    at temperature: Double,
    points: [CurvePoint],
    mode: InterpolationMode,
    axisScale: CurveAxisScale? = nil
  ) -> Double {
    let sorted = points.sorted { $0.temperature < $1.temperature }
    guard
      let firstPoint = sorted.first,
      let lastPoint = sorted.last,
      firstPoint.temperature != lastPoint.temperature
    else { return 0 }

    let sampleRadiusC = CurveInterpolationConstants.sampleRadiusC
    var lowTemperature = max(firstPoint.temperature, temperature - sampleRadiusC)
    var highTemperature = min(lastPoint.temperature, temperature + sampleRadiusC)

    if abs(highTemperature - lowTemperature) <= CurveInterpolationConstants.divisionEpsilon {
      lowTemperature = max(
        firstPoint.temperature,
        temperature - sampleRadiusC * CurveInterpolationConstants.sampleRadiusExpandFactor)
      highTemperature = min(
        lastPoint.temperature,
        temperature + sampleRadiusC * CurveInterpolationConstants.sampleRadiusExpandFactor)
    }

    let temperatureDelta = highTemperature - lowTemperature
    guard abs(temperatureDelta) > CurveInterpolationConstants.divisionEpsilon else { return 0 }

    let lowPercent = evaluate(
      at: lowTemperature,
      points: sorted,
      mode: mode,
      axisScale: axisScale
    )
    let highPercent = evaluate(
      at: highTemperature,
      points: sorted,
      mode: mode,
      axisScale: axisScale
    )
    return abs(highPercent - lowPercent) / temperatureDelta
  }

  static func linear(at temperature: Double, points: [CurvePoint]) -> Double {
    guard !points.isEmpty else { return 0 }
    let sorted = points.sorted { $0.temperature < $1.temperature }

    guard let firstPoint = sorted.first, let lastPoint = sorted.last else { return 0 }
    if temperature <= firstPoint.temperature { return max(0, firstPoint.fanPercent) }
    if temperature >= lastPoint.temperature { return min(1, lastPoint.fanPercent) }

    for pointIndex in 0..<(sorted.count - 1) {
      let p1 = sorted[pointIndex]
      let p2 = sorted[pointIndex + 1]
      if temperature >= p1.temperature, temperature <= p2.temperature {
        let fraction = (temperature - p1.temperature) / (p2.temperature - p1.temperature)
        return max(0, min(1, p1.fanPercent + fraction * (p2.fanPercent - p1.fanPercent)))
      }
    }

    return max(0, min(1, lastPoint.fanPercent))
  }

  /// Shape-preserving Hermite interpolation keeps the persisted `catmullRom`
  /// mode smooth without allowing the curve to overshoot between controls.
  static func catmullRom(
    at temperature: Double,
    points: [CurvePoint],
    axisScale: CurveAxisScale? = nil
  ) -> Double {
    axisHermite(
      at: temperature,
      points: points,
      axisScale: CurveInterpolationAxisHelpers.resolvedAxisScale(
        points: points,
        preferredAxisScale: axisScale
      )
    )
      ?? linear(at: temperature, points: points)
  }

  private static func axisHermite(
    at temperature: Double,
    points: [CurvePoint],
    axisScale: CurveAxisScale?
  ) -> Double? {
    guard !points.isEmpty else { return 0 }
    guard let axisScale else { return nil }
    let sorted = points.sorted { $0.temperature < $1.temperature }
    let range = axisScale.range
    guard
      let firstPoint = sorted.first,
      let lastPoint = sorted.last,
      abs(firstPoint.temperature - range.lowerBound)
        < CurveInterpolationConstants.axisSnapTolerance,
      abs(lastPoint.temperature - range.upperBound)
        < CurveInterpolationConstants.axisSnapTolerance
    else { return nil }

    if temperature <= firstPoint.temperature { return max(0, firstPoint.fanPercent) }
    if temperature >= lastPoint.temperature { return min(1, lastPoint.fanPercent) }

    let fractions = sorted.map { axisScale.fraction(for: $0.temperature) }
    let percents = sorted.map { max(0, min(1, $0.fanPercent)) }
    let tangents = shapePreservingTangents(xs: fractions, ys: percents)
    let currentFraction = axisScale.fraction(for: temperature)

    for pointIndex in 0..<(sorted.count - 1) {
      let leftPoint = sorted[pointIndex]
      let rightPoint = sorted[pointIndex + 1]
      if temperature >= leftPoint.temperature, temperature <= rightPoint.temperature {
        let leftFraction = fractions[pointIndex]
        let rightFraction = fractions[pointIndex + 1]
        guard rightFraction != leftFraction else {
          return percents[pointIndex + 1]
        }
        let percent = hermiteValue(
          segment: HermiteSegment(
            currentFraction: currentFraction,
            leftFraction: leftFraction,
            rightFraction: rightFraction,
            leftPercent: percents[pointIndex],
            rightPercent: percents[pointIndex + 1],
            leftTangent: tangents[pointIndex],
            rightTangent: tangents[pointIndex + 1]
          )
        )
        let low = min(percents[pointIndex], percents[pointIndex + 1])
        let high = max(percents[pointIndex], percents[pointIndex + 1])
        return max(0, min(1, max(low, min(high, percent))))
      }
    }

    return max(0, min(1, lastPoint.fanPercent))
  }

  private static func shapePreservingTangents(xs: [Double], ys: [Double]) -> [Double] {
    guard
      xs.count == ys.count,
      xs.count >= CurveInterpolationConstants.minTangentPoints
    else { return [] }
    guard xs.count > CurveInterpolationConstants.minInteriorStencilPoints else {
      let slope = segmentSlope(x0: xs[0], x1: xs[1], y0: ys[0], y1: ys[1])
      return [slope, slope]
    }

    let slopes = segmentSlopes(xs: xs, ys: ys)
    var tangents = [Double](repeating: 0, count: xs.count)
    let secondNeighbor = CurveInterpolationConstants.endpointSecondNeighborOffset
    let thirdNeighbor = CurveInterpolationConstants.endpointThirdNeighborOffset
    tangents[0] = endpointTangent(
      h0: xs[1] - xs[0],
      h1: xs[secondNeighbor] - xs[1],
      d0: slopes[0],
      d1: slopes[1]
    )
    tangents[xs.count - 1] = endpointTangent(
      h0: xs[xs.count - 1] - xs[xs.count - secondNeighbor],
      h1: xs[xs.count - secondNeighbor] - xs[xs.count - thirdNeighbor],
      d0: slopes[slopes.count - 1],
      d1: slopes[slopes.count - secondNeighbor]
    )

    for pointIndex in 1..<(xs.count - 1) {
      let leftSlope = slopes[pointIndex - 1]
      let rightSlope = slopes[pointIndex]
      if leftSlope * rightSlope <= 0 {
        tangents[pointIndex] = 0
        continue
      }

      let leftWidth = xs[pointIndex] - xs[pointIndex - 1]
      let rightWidth = xs[pointIndex + 1] - xs[pointIndex]
      let leftWeight = CurveInterpolationConstants.hermiteCoeff2 * rightWidth + leftWidth
      let rightWeight = rightWidth + CurveInterpolationConstants.hermiteCoeff2 * leftWidth
      tangents[pointIndex] =
        (leftWeight + rightWeight) / ((leftWeight / leftSlope) + (rightWeight / rightSlope))
    }

    return tangents
  }

  private static func segmentSlopes(xs: [Double], ys: [Double]) -> [Double] {
    (0..<(xs.count - 1)).map { pointIndex in
      segmentSlope(
        x0: xs[pointIndex],
        x1: xs[pointIndex + 1],
        y0: ys[pointIndex],
        y1: ys[pointIndex + 1]
      )
    }
  }

  private static func segmentSlope(x0: Double, x1: Double, y0: Double, y1: Double) -> Double {
    let width = x1 - x0
    guard abs(width) > CurveInterpolationConstants.divisionEpsilon else { return 0 }
    return (y1 - y0) / width
  }

  private static func endpointTangent(h0: Double, h1: Double, d0: Double, d1: Double) -> Double {
    guard h0 > 0, h1 > 0 else { return 0 }
    var tangent =
      ((CurveInterpolationConstants.hermiteCoeff2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
    if tangent * d0 <= 0 {
      tangent = 0
    } else if d0 * d1 < 0, abs(tangent) > abs(CurveInterpolationConstants.hermiteCoeff3 * d0) {
      tangent = CurveInterpolationConstants.hermiteCoeff3 * d0
    }
    return tangent
  }

  private static func hermiteValue(segment: HermiteSegment) -> Double {
    let width = segment.rightFraction - segment.leftFraction
    guard abs(width) > CurveInterpolationConstants.divisionEpsilon else {
      return segment.rightPercent
    }

    let progress = max(0, min(1, (segment.currentFraction - segment.leftFraction) / width))
    let progressSquared = progress * progress
    let progressCubed = progressSquared * progress
    let h00 =
      CurveInterpolationConstants.hermiteCoeff2 * progressCubed - CurveInterpolationConstants
      .hermiteCoeff3 * progressSquared + 1
    let h10 =
      progressCubed - CurveInterpolationConstants.hermiteCoeff2 * progressSquared + progress
    let h01 =
      -CurveInterpolationConstants.hermiteCoeff2 * progressCubed + CurveInterpolationConstants
      .hermiteCoeff3 * progressSquared
    let h11 = progressCubed - progressSquared
    return h00 * segment.leftPercent
      + h10 * width * segment.leftTangent
      + h01 * segment.rightPercent
      + h11 * width * segment.rightTangent
  }

  /// Generate path points for rendering the curve in a Canvas
  static func pathPoints(
    points: [CurvePoint],
    mode: InterpolationMode,
    tempRange: ClosedRange<Double>,
    steps: Int = CurveInterpolationConstants.defaultPathSteps,
    axisScale: CurveAxisScale? = nil
  ) -> [(temperature: Double, fanPercent: Double)] {
    let sorted = points.sorted { $0.temperature < $1.temperature }
    guard !sorted.isEmpty else { return [] }

    var result: [(Double, Double)] = []
    let safeSteps = max(1, steps)
    let resolvedAxisScale = CurveInterpolationAxisHelpers.resolvedAxisScale(
      points: sorted,
      preferredAxisScale: axisScale
    )

    for stepIndex in 0...safeSteps {
      let fraction = Double(stepIndex) / Double(safeSteps)
      let temp = CurveInterpolationAxisHelpers.pathTemperature(
        at: fraction,
        in: tempRange,
        mode: mode,
        axisScale: resolvedAxisScale
      )
      let percent = evaluate(
        at: temp,
        points: sorted,
        mode: mode,
        axisScale: resolvedAxisScale
      )
      result.append((temp, percent))
    }

    return result
  }
}
