//
//  LoadAssistStore.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let loadAssistStoreLog = AppLog.make(category: "LoadAssistStore")

enum LoadAssistStore {
  private static let enabledMigrationVersion = 1
  private static let numericChartResetVersion = 5
  private static let migrationVersion = numericChartResetVersion
  private static let defaultFloorPercent = 60.0
  private static let controlPointCount = 4
  private static let minimumInteriorLoadGap = 1.0
  private static let defaultLiftStartLoad = 55.0
  private static let defaultFullAssistLoad = 70.0

  static func migrateLegacyIfNeeded(defaults: UserDefaults) {
    let currentMigrationVersion = defaults.integer(
      forKey: SharedConfigKeys.loadAssistMigrationVersion
    )
    if currentMigrationVersion >= migrationVersion {
      return
    }

    if currentMigrationVersion < enabledMigrationVersion {
      let hasLegacyEnabled =
        defaults.object(forKey: SharedConfigKeys.loadFloorEnabled) != nil
      if hasLegacyEnabled {
        let enabled = defaults.bool(forKey: SharedConfigKeys.loadFloorEnabled)
        for kind in LoadAssistKind.allCases
        where defaults.object(forKey: kind.enabledKey) == nil {
          defaults.set(enabled, forKey: kind.enabledKey)
        }
      }
    }

    if currentMigrationVersion < numericChartResetVersion {
      for kind in LoadAssistKind.allCases
      where shouldResetLegacyCurve(kind, defaults: defaults) {
        savePoints(defaultPoints(), kind: kind, defaults: defaults)
      }
    }

    defaults.set(migrationVersion, forKey: SharedConfigKeys.loadAssistMigrationVersion)
  }

  static func loadEnabled(_ kind: LoadAssistKind, defaults: UserDefaults) -> Bool {
    migrateLegacyIfNeeded(defaults: defaults)
    return defaults.bool(forKey: kind.enabledKey)
  }

  static func saveEnabled(_ enabled: Bool, kind: LoadAssistKind, defaults: UserDefaults) {
    defaults.set(enabled, forKey: kind.enabledKey)
  }

  static func loadPoints(_ kind: LoadAssistKind, defaults: UserDefaults) -> [CurvePoint] {
    migrateLegacyIfNeeded(defaults: defaults)
    guard let data = defaults.data(forKey: kind.curvePointsKey) else {
      return defaultPoints()
    }
    let decoded: [CurvePoint]
    do {
      decoded = try JSONDecoder().decode([CurvePoint].self, from: data)
    } catch {
      loadAssistStoreLog.notice(
        "load_assist.decode_failed kind=\(kind.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=default"
      )
      return defaultPoints()
    }
    guard decoded.count == controlPointCount else {
      loadAssistStoreLog.notice(
        "load_assist.invalid_point_count kind=\(kind.rawValue, privacy: .public) point_count=\(decoded.count, privacy: .public) recovery=default"
      )
      return defaultPoints()
    }
    return normalizedPoints(decoded)
  }

  static func savePoints(
    _ points: [CurvePoint],
    kind: LoadAssistKind,
    defaults: UserDefaults
  ) {
    let normalized = normalizedPoints(points)
    do {
      let data = try JSONEncoder().encode(normalized)
      defaults.set(data, forKey: kind.curvePointsKey)
    } catch {
      loadAssistStoreLog.error(
        "load_assist.encode_failed kind=\(kind.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=skip-write"
      )
    }
  }

  static func defaultPoints() -> [CurvePoint] {
    let floorPercent = max(0.0, min(1.0, defaultFloorPercent / 100.0))
    let range = LoadAssistCurveColumns.xRange

    return [
      CurvePoint(temperature: range.lowerBound, fanPercent: 0),
      CurvePoint(temperature: defaultLiftStartLoad, fanPercent: 0),
      CurvePoint(
        temperature: defaultFullAssistLoad,
        fanPercent: floorPercent
      ),
      CurvePoint(
        temperature: range.upperBound,
        fanPercent: floorPercent
      ),
    ]
  }

  static func normalizedPoints(_ points: [CurvePoint]) -> [CurvePoint] {
    guard points.count == controlPointCount else { return defaultPoints() }

    var normalized = points.sorted { $0.temperature < $1.temperature }
    let lastIndex = normalized.index(before: normalized.endIndex)
    let minimumLoad = LoadAssistCurveColumns.xRange.lowerBound
    let maximumLoad = LoadAssistCurveColumns.xRange.upperBound

    normalized[0].temperature = minimumLoad
    normalized[lastIndex].temperature = maximumLoad

    if lastIndex > 1 {
      for pointIndex in 1..<lastIndex {
        let remainingPointCount = lastIndex - pointIndex
        let minimumPointLoad =
          normalized[pointIndex - 1].temperature + minimumInteriorLoadGap
        let maximumPointLoad =
          maximumLoad - Double(remainingPointCount) * minimumInteriorLoadGap
        normalized[pointIndex].temperature = max(
          minimumPointLoad,
          min(maximumPointLoad, normalized[pointIndex].temperature)
        )
      }

      for pointIndex in stride(from: lastIndex - 1, through: 1, by: -1) {
        let minimumPointLoad =
          normalized[pointIndex - 1].temperature + minimumInteriorLoadGap
        let maximumPointLoad =
          normalized[pointIndex + 1].temperature - minimumInteriorLoadGap
        normalized[pointIndex].temperature = max(
          minimumPointLoad,
          min(maximumPointLoad, normalized[pointIndex].temperature)
        )
      }
    }

    let normalizedPercents = CurvePercentConstraints.monotonicPercents(
      normalized.map(\.fanPercent)
    )

    for pointIndex in normalized.indices {
      normalized[pointIndex].fanPercent = normalizedPercents[pointIndex]
    }

    return normalized
  }

  static func updatedPoints(
    _ points: [CurvePoint],
    draggedIndex index: Int,
    proposedLoad: Double,
    proposedPercent: Double
  ) -> [CurvePoint] {
    let normalized = normalizedPoints(points)
    guard normalized.indices.contains(index) else { return normalized }

    var updated = normalized
    let lastIndex = updated.index(before: updated.endIndex)

    if index > 0, index < lastIndex {
      let minimumLoad = updated[index - 1].temperature + minimumInteriorLoadGap
      let maximumLoad = updated[index + 1].temperature - minimumInteriorLoadGap
      updated[index].temperature = max(minimumLoad, min(maximumLoad, proposedLoad))
    }

    let updatedPercents = CurvePercentConstraints.updatedPercents(
      updated.map(\.fanPercent),
      draggedIndex: index,
      proposedPercent: proposedPercent
    )

    for pointIndex in updated.indices {
      updated[pointIndex].fanPercent = updatedPercents[pointIndex]
    }

    return normalizedPoints(updated)
  }

  private static func shouldResetLegacyCurve(
    _ kind: LoadAssistKind,
    defaults: UserDefaults
  ) -> Bool {
    defaults.object(forKey: kind.curvePointsKey) != nil
      || defaults.object(forKey: kind.legacyThresholdKey) != nil
  }
}
