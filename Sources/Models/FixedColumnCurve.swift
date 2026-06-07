//
//  FixedColumnCurve.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-06-04.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - CurvePercentConstraints

enum CurvePercentConstraints {
  static func updatedPercents(
    _ percents: [Double],
    draggedIndex index: Int,
    proposedPercent: Double
  ) -> [Double] {
    guard percents.indices.contains(index) else { return percents }

    var updatedPercents = percents.map { max(0.0, min(1.0, $0)) }
    updatedPercents[index] = max(0.0, min(1.0, proposedPercent))

    if index > 0 {
      for pointIndex in stride(from: index - 1, through: 0, by: -1) {
        let nextPercent = updatedPercents[pointIndex + 1]
        updatedPercents[pointIndex] = min(updatedPercents[pointIndex], nextPercent)
      }
    }

    if index < updatedPercents.count - 1 {
      for pointIndex in (index + 1)..<updatedPercents.count {
        let previousPercent = updatedPercents[pointIndex - 1]
        updatedPercents[pointIndex] = max(updatedPercents[pointIndex], previousPercent)
      }
    }

    return updatedPercents
  }

  static func monotonicPercents(_ percents: [Double]) -> [Double] {
    guard !percents.isEmpty else { return [] }

    var normalizedPercents: [Double] = []
    normalizedPercents.reserveCapacity(percents.count)

    var previousPercent = 0.0
    for percent in percents {
      let clampedPercent = max(0.0, min(1.0, percent))
      let monotonicPercent = max(previousPercent, clampedPercent)
      normalizedPercents.append(monotonicPercent)
      previousPercent = monotonicPercent
    }

    return normalizedPercents
  }
}

// MARK: - FixedColumnCurve

enum FixedColumnCurve {
  static func updatedPoints(
    _ points: [CurvePoint],
    draggedIndex index: Int,
    proposedPercent: Double
  ) -> [CurvePoint] {
    guard points.indices.contains(index) else { return points }

    var updated = points
    let percents = CurvePercentConstraints.updatedPercents(
      updated.map(\.fanPercent),
      draggedIndex: index,
      proposedPercent: proposedPercent
    )

    for pointIndex in updated.indices {
      updated[pointIndex].fanPercent = percents[pointIndex]
    }

    return updated
  }
}
