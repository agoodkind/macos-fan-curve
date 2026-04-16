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
      if temperature >= p1.temperature && temperature <= p2.temperature {
        let t = (temperature - p1.temperature) / (p2.temperature - p1.temperature)
        return max(0, min(1, p1.fanPercent + t * (p2.fanPercent - p1.fanPercent)))
      }
    }

    return max(0, min(1, sorted.last!.fanPercent))
  }

  static func catmullRom(at temperature: Double, points: [CurvePoint]) -> Double {
    guard points.count >= 2 else { return linear(at: temperature, points: points) }
    let sorted = points.sorted { $0.temperature < $1.temperature }

    if temperature <= sorted.first!.temperature { return max(0, sorted.first!.fanPercent) }
    if temperature >= sorted.last!.temperature { return min(1, sorted.last!.fanPercent) }

    // Find the bracketing segment
    var segIdx = 0
    for i in 0..<(sorted.count - 1) {
      if temperature >= sorted[i].temperature && temperature <= sorted[i + 1].temperature {
        segIdx = i
        break
      }
    }

    // Get 4 points for Catmull-Rom (with virtual endpoints)
    let p0 = segIdx > 0 ? sorted[segIdx - 1] : sorted[segIdx]
    let p1 = sorted[segIdx]
    let p2 = sorted[segIdx + 1]
    let p3 = segIdx + 2 < sorted.count ? sorted[segIdx + 2] : sorted[segIdx + 1]

    let t = (temperature - p1.temperature) / (p2.temperature - p1.temperature)
    let t2 = t * t
    let t3 = t2 * t

    // Catmull-Rom matrix multiplication
    let v = 0.5 * (
      (2.0 * p1.fanPercent)
        + (-p0.fanPercent + p2.fanPercent) * t
        + (2.0 * p0.fanPercent - 5.0 * p1.fanPercent + 4.0 * p2.fanPercent - p3.fanPercent) * t2
        + (-p0.fanPercent + 3.0 * p1.fanPercent - 3.0 * p2.fanPercent + p3.fanPercent) * t3
    )

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
