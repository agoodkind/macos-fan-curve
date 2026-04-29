//
//  CurveColumns.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026
//

import Foundation

enum CurveColumns {
    static let tempRange: ClosedRange<Double> = 20...110
    static let pointCount: Int = 8

    static func temperatures(count: Int = pointCount) -> [Double] {
        if count == pointCount {
            // Keep early anchors intuitive, then spend extra columns in the
            // thermally relevant high range.
            return [20, 40, 60, 72, 83, 93, 102, 110]
        }

        guard count > 1 else { return [tempRange.lowerBound] }
        let step = (tempRange.upperBound - tempRange.lowerBound) / Double(count - 1)
        return (0..<count).map { tempRange.lowerBound + Double($0) * step }
    }

    static func normalize(_ points: [CurvePoint], count: Int = pointCount) -> [CurvePoint] {
        guard !points.isEmpty else { return [] }
        let sorted = points.sorted { $0.temperature < $1.temperature }
        return temperatures(count: count).map { temp in
            CurvePoint(
                temperature: temp,
                fanPercent: CurveInterpolation.evaluate(at: temp, points: sorted, mode: .catmullRom)
            )
        }
    }
}
