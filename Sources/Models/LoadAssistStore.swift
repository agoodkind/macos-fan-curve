//
//  LoadAssistStore.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026
//

import AppLog
import Foundation

private let loadAssistStoreLog = AppLog.make(category: "LoadAssistStore")

enum LoadAssistStore {
    private static let migrationVersion = 1
    private static let defaultThreshold = 70.0
    private static let defaultFloorPercent = 60.0
    private static let rampLeadIn = 15.0
    static let loadRange: ClosedRange<Double> = 0...100

    static func migrateLegacyIfNeeded(defaults: UserDefaults) {
        let currentMigrationVersion = defaults.integer(
            forKey: SharedConfigKeys.loadAssistMigrationVersion
        )
        if currentMigrationVersion >= migrationVersion {
            return
        }

        let hasLegacyValues =
            defaults.object(forKey: SharedConfigKeys.loadFloorEnabled) != nil
            || defaults.object(forKey: SharedConfigKeys.loadFloorThreshold) != nil
            || defaults.object(forKey: SharedConfigKeys.gpuLoadFloorThreshold) != nil
            || defaults.object(forKey: SharedConfigKeys.loadFloorPercent) != nil

        guard hasLegacyValues else {
            defaults.set(migrationVersion, forKey: SharedConfigKeys.loadAssistMigrationVersion)
            return
        }

        let enabled = defaults.bool(forKey: SharedConfigKeys.loadFloorEnabled)
        let storedFloor = defaults.double(forKey: SharedConfigKeys.loadFloorPercent)
        let floorPercent = storedFloor > 0 ? storedFloor : defaultFloorPercent

        for kind in LoadAssistKind.allCases {
            let thresholdValue = defaults.double(forKey: kind.legacyThresholdKey)
            let threshold = thresholdValue > 0 ? thresholdValue : defaultThreshold
            if defaults.object(forKey: kind.enabledKey) == nil {
                defaults.set(enabled, forKey: kind.enabledKey)
            }
            if defaults.object(forKey: kind.curvePointsKey) == nil {
                savePoints(
                    defaultPoints(threshold: threshold, floorPercent: floorPercent),
                    kind: kind,
                    defaults: defaults
                )
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
        return normalizedPoints(decoded)
    }

    static func savePoints(_ points: [CurvePoint], kind: LoadAssistKind, defaults: UserDefaults) {
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
        defaultPoints(threshold: defaultThreshold, floorPercent: defaultFloorPercent)
    }

    static func defaultPoints(threshold: Double, floorPercent: Double) -> [CurvePoint] {
        let rampStart = max(loadRange.lowerBound, threshold - rampLeadIn)
        let clampedThreshold = min(loadRange.upperBound, max(loadRange.lowerBound, threshold))
        let floor = max(0.0, min(1.0, floorPercent / 100.0))
        return normalizedPoints([
            CurvePoint(temperature: 0, fanPercent: 0),
            CurvePoint(temperature: rampStart, fanPercent: 0),
            CurvePoint(temperature: clampedThreshold, fanPercent: floor),
            CurvePoint(temperature: 100, fanPercent: floor),
        ])
    }

    static func normalizedPoints(_ points: [CurvePoint]) -> [CurvePoint] {
        let sorted = points.sorted { $0.temperature < $1.temperature }
        guard !sorted.isEmpty else { return defaultPoints() }

        var normalized = sorted.enumerated().map { index, point in
            CurvePoint(
                temperature: clampedTemperature(
                    point.temperature, index: index, count: sorted.count),
                fanPercent: max(0.0, min(1.0, point.fanPercent))
            )
        }

        if normalized.first?.temperature ?? 0 > loadRange.lowerBound {
            normalized.insert(
                CurvePoint(
                    temperature: loadRange.lowerBound, fanPercent: normalized.first?.fanPercent ?? 0
                ), at: 0)
        }
        if normalized.last?.temperature ?? 100 < loadRange.upperBound {
            normalized.append(
                CurvePoint(
                    temperature: loadRange.upperBound, fanPercent: normalized.last?.fanPercent ?? 0)
            )
        }

        var previousTemp = loadRange.lowerBound
        var previousPercent = 0.0
        for index in normalized.indices {
            let maxTemp =
                index == normalized.indices.last
                ? loadRange.upperBound : loadRange.upperBound - Double(normalized.count - index - 1)
            let nextTemp = max(previousTemp, min(maxTemp, normalized[index].temperature))
            let nextPercent = max(previousPercent, min(1.0, normalized[index].fanPercent))
            normalized[index].temperature = nextTemp
            normalized[index].fanPercent = nextPercent
            previousTemp = nextTemp + 1
            previousPercent = nextPercent
        }

        normalized[0].temperature = loadRange.lowerBound
        normalized[normalized.count - 1].temperature = loadRange.upperBound
        return normalized
    }

    private static func clampedTemperature(_ value: Double, index: Int, count: Int) -> Double {
        let minTemp = loadRange.lowerBound + Double(index)
        let maxTemp = loadRange.upperBound - Double(max(0, count - index - 1))
        return min(maxTemp, max(minTemp, value))
    }
}
