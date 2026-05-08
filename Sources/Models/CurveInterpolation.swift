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

    /// Rope interpolation keeps the persisted `catmullRom` mode authoritative
    /// while making the curve behave like a tensioned line through the visible
    /// control points.
    static func catmullRom(at temperature: Double, points: [CurvePoint]) -> Double {
        axisRope(at: temperature, points: points)
            ?? linear(at: temperature, points: points)
    }

    private static func axisRope(at temperature: Double, points: [CurvePoint]) -> Double? {
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

        for pointIndex in 0..<(sorted.count - 1) {
            let leftPoint = sorted[pointIndex]
            let rightPoint = sorted[pointIndex + 1]
            if temperature >= leftPoint.temperature, temperature <= rightPoint.temperature {
                let leftFraction = scale.fraction(for: leftPoint.temperature)
                let rightFraction = scale.fraction(for: rightPoint.temperature)
                let currentFraction = scale.fraction(for: temperature)
                guard rightFraction != leftFraction else {
                    return max(0, min(1, rightPoint.fanPercent))
                }
                let segmentFraction = (currentFraction - leftFraction) / (rightFraction - leftFraction)
                let percent =
                    leftPoint.fanPercent
                    + segmentFraction * (rightPoint.fanPercent - leftPoint.fanPercent)
                return max(0, min(1, percent))
            }
        }

        return max(0, min(1, lastPoint.fanPercent))
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
