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

        if temperature <= sorted.first!.temperature { return max(0, sorted.first!.fanPercent) }
        if temperature >= sorted.last!.temperature { return min(1, sorted.last!.fanPercent) }

        for i in 0..<(sorted.count - 1) {
            let p1 = sorted[i]
            let p2 = sorted[i + 1]
            if temperature >= p1.temperature, temperature <= p2.temperature {
                let t = (temperature - p1.temperature) / (p2.temperature - p1.temperature)
                return max(0, min(1, p1.fanPercent + t * (p2.fanPercent - p1.fanPercent)))
            }
        }

        return max(0, min(1, sorted.last!.fanPercent))
    }

    /// Monotone cubic interpolation (Fritsch-Carlson). Smooth curves that never
    /// overshoot between control points, which is critical for fan curves where
    /// you never want the speed to dip below a control point's value.
    static func catmullRom(at temperature: Double, points: [CurvePoint]) -> Double {
        guard points.count >= 2 else { return linear(at: temperature, points: points) }
        let sorted = points.sorted { $0.temperature < $1.temperature }
        let n = sorted.count

        if temperature <= sorted[0].temperature { return max(0, sorted[0].fanPercent) }
        if temperature >= sorted[n - 1].temperature { return min(1, sorted[n - 1].fanPercent) }

        // Compute slopes (Fritsch-Carlson monotone method)
        var dx = [Double](repeating: 0, count: n - 1)
        var dy = [Double](repeating: 0, count: n - 1)
        var slopes = [Double](repeating: 0, count: n - 1)

        for i in 0..<(n - 1) {
            dx[i] = sorted[i + 1].temperature - sorted[i].temperature
            dy[i] = sorted[i + 1].fanPercent - sorted[i].fanPercent
            slopes[i] = dx[i] != 0 ? dy[i] / dx[i] : 0
        }

        // Compute tangents with monotonicity constraint
        var tangents = [Double](repeating: 0, count: n)
        tangents[0] = slopes[0]
        tangents[n - 1] = slopes[n - 2]

        for i in 1..<(n - 1) {
            if slopes[i - 1] * slopes[i] <= 0 {
                tangents[i] = 0
            } else {
                tangents[i] = (slopes[i - 1] + slopes[i]) / 2.0
            }
        }

        // Fritsch-Carlson monotonicity fix
        for i in 0..<(n - 1) {
            if slopes[i] == 0 {
                tangents[i] = 0
                tangents[i + 1] = 0
            } else {
                let alpha = tangents[i] / slopes[i]
                let beta = tangents[i + 1] / slopes[i]
                let sum = alpha * alpha + beta * beta
                if sum > 9 {
                    let tau = 3.0 / sum.squareRoot()
                    tangents[i] = tau * alpha * slopes[i]
                    tangents[i + 1] = tau * beta * slopes[i]
                }
            }
        }

        // Find segment and interpolate
        var seg = 0
        for i in 0..<(n - 1) where temperature >= sorted[i].temperature && temperature <= sorted[i + 1].temperature {
            seg = i
            break
        }

        let h = dx[seg]
        let t = (temperature - sorted[seg].temperature) / h
        let t2 = t * t
        let t3 = t2 * t

        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2

        let v =
            h00 * sorted[seg].fanPercent
            + h10 * h * tangents[seg]
            + h01 * sorted[seg + 1].fanPercent
            + h11 * h * tangents[seg + 1]

        return max(0, min(1, v))
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

        for i in 0...steps {
            let temp = tempRange.lowerBound + Double(i) * step
            let percent = evaluate(at: temp, points: sorted, mode: mode)
            result.append((temp, percent))
        }

        return result
    }
}
