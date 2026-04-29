//
//  CurveInterpolation.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import Foundation

enum CurveInterpolation {

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

    /// Monotone cubic interpolation (Fritsch-Carlson). Smooth curves that never
    /// overshoot between control points, which is critical for fan curves where
    /// you never want the speed to dip below a control point's value.
    static func catmullRom(at temperature: Double, points: [CurvePoint]) -> Double {
        guard points.count >= 2 else { return linear(at: temperature, points: points) }
        let sorted = points.sorted { $0.temperature < $1.temperature }
        let pointCount = sorted.count

        if temperature <= sorted[0].temperature { return max(0, sorted[0].fanPercent) }
        if temperature >= sorted[pointCount - 1].temperature { return min(1, sorted[pointCount - 1].fanPercent) }

        // Compute slopes (Fritsch-Carlson monotone method)
        var dx = [Double](repeating: 0, count: pointCount - 1)
        var dy = [Double](repeating: 0, count: pointCount - 1)
        var slopes = [Double](repeating: 0, count: pointCount - 1)

        for pointIndex in 0..<(pointCount - 1) {
            dx[pointIndex] = sorted[pointIndex + 1].temperature - sorted[pointIndex].temperature
            dy[pointIndex] = sorted[pointIndex + 1].fanPercent - sorted[pointIndex].fanPercent
            slopes[pointIndex] = dx[pointIndex] != 0 ? dy[pointIndex] / dx[pointIndex] : 0
        }

        // Compute tangents with monotonicity constraint
        var tangents = [Double](repeating: 0, count: pointCount)
        tangents[0] = slopes[0]
        tangents[pointCount - 1] = slopes[pointCount - 2]

        for pointIndex in 1..<(pointCount - 1) {
            if slopes[pointIndex - 1] * slopes[pointIndex] <= 0 {
                tangents[pointIndex] = 0
            } else {
                tangents[pointIndex] = (slopes[pointIndex - 1] + slopes[pointIndex]) / 2.0
            }
        }

        // Fritsch-Carlson monotonicity fix
        for pointIndex in 0..<(pointCount - 1) {
            if slopes[pointIndex] == 0 {
                tangents[pointIndex] = 0
                tangents[pointIndex + 1] = 0
            } else {
                let alpha = tangents[pointIndex] / slopes[pointIndex]
                let beta = tangents[pointIndex + 1] / slopes[pointIndex]
                let sum = alpha * alpha + beta * beta
                if sum > 9 {
                    let tau = 3.0 / sum.squareRoot()
                    tangents[pointIndex] = tau * alpha * slopes[pointIndex]
                    tangents[pointIndex + 1] = tau * beta * slopes[pointIndex]
                }
            }
        }

        // Find segment and interpolate
        var seg = 0
        for pointIndex in 0..<(pointCount - 1)
        where temperature >= sorted[pointIndex].temperature && temperature <= sorted[pointIndex + 1].temperature {
            seg = pointIndex
            break
        }

        let segmentWidth = dx[seg]
        let fraction = (temperature - sorted[seg].temperature) / segmentWidth
        let fractionSquared = fraction * fraction
        let fractionCubed = fractionSquared * fraction

        let h00 = 2 * fractionCubed - 3 * fractionSquared + 1
        let h10 = fractionCubed - 2 * fractionSquared + fraction
        let h01 = -2 * fractionCubed + 3 * fractionSquared
        let h11 = fractionCubed - fractionSquared

        let interpolatedPercent =
            h00 * sorted[seg].fanPercent
            + h10 * segmentWidth * tangents[seg]
            + h01 * sorted[seg + 1].fanPercent
            + h11 * segmentWidth * tangents[seg + 1]

        return max(0, min(1, interpolatedPercent))
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
        let step = (tempRange.upperBound - tempRange.lowerBound) / Double(steps)

        for stepIndex in 0...steps {
            let temp = tempRange.lowerBound + Double(stepIndex) * step
            let percent = evaluate(at: temp, points: sorted, mode: mode)
            result.append((temp, percent))
        }

        return result
    }
}
