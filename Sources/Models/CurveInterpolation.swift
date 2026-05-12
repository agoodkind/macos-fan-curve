//
//  CurveInterpolation.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import Foundation

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
        mode: InterpolationMode
    ) -> Double {
        switch mode {
        case .linear: return linear(at: temperature, points: points)
        case .catmullRom: return catmullRom(at: temperature, points: points)
        }
    }

    static func localResponse(
        at temperature: Double,
        points: [CurvePoint],
        mode: InterpolationMode
    ) -> FanResponse {
        FanResponse.responseValue(
            forSlopePercentPerC: localSlopePercentPerC(
                at: temperature,
                points: points,
                mode: mode
            )
        )
    }

    static func localSlopePercentPerC(
        at temperature: Double,
        points: [CurvePoint],
        mode: InterpolationMode
    ) -> Double {
        let sorted = points.sorted { $0.temperature < $1.temperature }
        guard
            let firstPoint = sorted.first,
            let lastPoint = sorted.last,
            firstPoint.temperature != lastPoint.temperature
        else { return 0 }

        let sampleRadiusC = 1.0
        var lowTemperature = max(firstPoint.temperature, temperature - sampleRadiusC)
        var highTemperature = min(lastPoint.temperature, temperature + sampleRadiusC)

        if abs(highTemperature - lowTemperature) <= 0.000001 {
            lowTemperature = max(firstPoint.temperature, temperature - sampleRadiusC * 2)
            highTemperature = min(lastPoint.temperature, temperature + sampleRadiusC * 2)
        }

        let temperatureDelta = highTemperature - lowTemperature
        guard abs(temperatureDelta) > 0.000001 else { return 0 }

        let lowPercent = evaluate(at: lowTemperature, points: sorted, mode: mode)
        let highPercent = evaluate(at: highTemperature, points: sorted, mode: mode)
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
    static func catmullRom(at temperature: Double, points: [CurvePoint]) -> Double {
        axisHermite(at: temperature, points: points)
            ?? linear(at: temperature, points: points)
    }

    private static func axisHermite(at temperature: Double, points: [CurvePoint]) -> Double? {
        guard !points.isEmpty else { return 0 }
        let sorted = points.sorted { $0.temperature < $1.temperature }
        let scale = TemperatureAxisScale.fanCurveDefault
        let range = scale.temperatureRangeC
        guard
            let firstPoint = sorted.first,
            let lastPoint = sorted.last,
            abs(firstPoint.temperature - range.lowerBound) < 0.001,
            abs(lastPoint.temperature - range.upperBound) < 0.001
        else { return nil }

        if temperature <= firstPoint.temperature { return max(0, firstPoint.fanPercent) }
        if temperature >= lastPoint.temperature { return min(1, lastPoint.fanPercent) }

        let fractions = sorted.map { scale.fraction(for: $0.temperature) }
        let percents = sorted.map { max(0, min(1, $0.fanPercent)) }
        let tangents = shapePreservingTangents(xs: fractions, ys: percents)
        let currentFraction = scale.fraction(for: temperature)

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
        guard xs.count == ys.count, xs.count >= 2 else { return [] }
        guard xs.count > 2 else {
            let slope = segmentSlope(x0: xs[0], x1: xs[1], y0: ys[0], y1: ys[1])
            return [slope, slope]
        }

        let slopes = segmentSlopes(xs: xs, ys: ys)
        var tangents = [Double](repeating: 0, count: xs.count)
        tangents[0] = endpointTangent(
            h0: xs[1] - xs[0],
            h1: xs[2] - xs[1],
            d0: slopes[0],
            d1: slopes[1]
        )
        tangents[xs.count - 1] = endpointTangent(
            h0: xs[xs.count - 1] - xs[xs.count - 2],
            h1: xs[xs.count - 2] - xs[xs.count - 3],
            d0: slopes[slopes.count - 1],
            d1: slopes[slopes.count - 2]
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
            let leftWeight = 2 * rightWidth + leftWidth
            let rightWeight = rightWidth + 2 * leftWidth
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
        guard abs(width) > 0.000001 else { return 0 }
        return (y1 - y0) / width
    }

    private static func endpointTangent(h0: Double, h1: Double, d0: Double, d1: Double) -> Double {
        guard h0 > 0, h1 > 0 else { return 0 }
        var tangent = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
        if tangent * d0 <= 0 {
            tangent = 0
        } else if d0 * d1 < 0, abs(tangent) > abs(3 * d0) {
            tangent = 3 * d0
        }
        return tangent
    }

    private static func hermiteValue(segment: HermiteSegment) -> Double {
        let width = segment.rightFraction - segment.leftFraction
        guard abs(width) > 0.000001 else { return segment.rightPercent }

        let progress = max(0, min(1, (segment.currentFraction - segment.leftFraction) / width))
        let progressSquared = progress * progress
        let progressCubed = progressSquared * progress
        let h00 = 2 * progressCubed - 3 * progressSquared + 1
        let h10 = progressCubed - 2 * progressSquared + progress
        let h01 = -2 * progressCubed + 3 * progressSquared
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
        steps: Int = 100
    ) -> [(temperature: Double, fanPercent: Double)] {
        let sorted = points.sorted { $0.temperature < $1.temperature }
        guard !sorted.isEmpty else { return [] }

        var result: [(Double, Double)] = []
        let safeSteps = max(1, steps)

        for stepIndex in 0...safeSteps {
            let fraction = Double(stepIndex) / Double(safeSteps)
            let temp = pathTemperature(at: fraction, in: tempRange, mode: mode)
            let percent = evaluate(at: temp, points: sorted, mode: mode)
            result.append((temp, percent))
        }

        return result
    }

    private static func pathTemperature(
        at fraction: Double,
        in tempRange: ClosedRange<Double>,
        mode: InterpolationMode
    ) -> Double {
        let scale = TemperatureAxisScale.fanCurveDefault
        let range = scale.temperatureRangeC
        let matchesDefaultRange =
            abs(tempRange.lowerBound - range.lowerBound) < 0.001
            && abs(tempRange.upperBound - range.upperBound) < 0.001
        if mode == .catmullRom, matchesDefaultRange {
            return scale.temperatureC(at: fraction)
        }

        return tempRange.lowerBound + fraction * (tempRange.upperBound - tempRange.lowerBound)
    }
}
