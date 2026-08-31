//
//  CurveColumns.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

import Foundation

enum CurveColumns {
  static let axisScale = TemperatureAxisScale.fanCurveDefault
  static let tempRange: ClosedRange<Double> = axisScale.temperatureRangeC
  static let pointCount: Int = 8

  static func temperatures(count: Int = pointCount) -> [Double] {
    if count == pointCount {
      return axisScale.controlPointTemperaturesC
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
