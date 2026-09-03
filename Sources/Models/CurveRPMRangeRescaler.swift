//
//  CurveRPMRangeRescaler.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-09-02.
//  Copyright © 2026, all rights reserved.
//

import Foundation

/// Converts curve control points so their commanded RPM stays fixed when
/// Overdrive or Underdrive changes the effective RPM range. Without this, a
/// control point keeps its stored percent and silently commands a different
/// RPM once the range it interpolates against changes underneath it.
///
/// This guarantee excludes points at 0%: `FanCommandMapping` treats 0% as a
/// floor whose commanded RPM is Underdrive's reported minimum or true 0, not
/// an interpolated value, and switching that floor between the two is the
/// entire point of the Underdrive toggle. Rescaling a 0% point onto some
/// above-zero percent to "preserve" its prior RPM would erase the floor the
/// curve author placed there.
struct CurveRPMRangeRescaler {
  let oldRange: (min: Float, max: Float)
  let newRange: (min: Float, max: Float)

  func rescale(_ points: [CurvePoint]) -> [CurvePoint] {
    guard oldRange.min != newRange.min || oldRange.max != newRange.max else { return points }
    return points.map { point in
      var rescaledPoint = point
      rescaledPoint.fanPercent = rescaledPercent(point.fanPercent)
      return rescaledPoint
    }
  }

  private func rescaledPercent(_ percent: Double) -> Double {
    // Leave the floor alone; see the type-level doc comment.
    guard percent > 0 else { return percent }
    let oldSpan = Double(oldRange.max) - Double(oldRange.min)
    let newSpan = Double(newRange.max) - Double(newRange.min)
    guard newSpan > 0 else { return percent }
    let rpm = Double(oldRange.min) + percent * oldSpan
    let rescaledPercent = (rpm - Double(newRange.min)) / newSpan
    return max(0, min(1, rescaledPercent))
  }
}
