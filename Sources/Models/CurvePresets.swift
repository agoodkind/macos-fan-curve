//
//  CurvePresets.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import Foundation

// MARK: - Preset point arrays

private enum CurvePresetPoints {
    // Balanced control-point temperatures (C) and fan percents (0 to 1).
    static let bal0T: Double = 20
    static let bal0P: Double = 0.0
    static let bal1T: Double = 50
    static let bal1P: Double = 0.0
    static let bal2T: Double = 55
    static let bal2P: Double = 0.30
    static let bal3T: Double = 65
    static let bal3P: Double = 0.35
    static let bal4T: Double = 75
    static let bal4P: Double = 0.45
    static let bal5T: Double = 85
    static let bal5P: Double = 0.60
    static let bal6T: Double = 95
    static let bal6P: Double = 0.80
    static let bal7T: Double = 100
    static let bal7P: Double = 1.0

    // Apple Silent control-point temperatures (C) and fan percents (0 to 1).
    static let sil0T: Double = 20
    static let sil0P: Double = 0.0
    static let sil1T: Double = 80
    static let sil1P: Double = 0.0
    static let sil2T: Double = 88
    static let sil2P: Double = 0.10
    static let sil3T: Double = 92
    static let sil3P: Double = 0.30
    static let sil4T: Double = 96
    static let sil4P: Double = 0.60
    static let sil5T: Double = 100
    static let sil5P: Double = 1.0

    // Aggressive control-point temperatures (C) and fan percents (0 to 1).
    static let agg0T: Double = 20
    static let agg0P: Double = 0.0
    static let agg1T: Double = 45
    static let agg1P: Double = 0.25
    static let agg2T: Double = 55
    static let agg2P: Double = 0.40
    static let agg3T: Double = 65
    static let agg3P: Double = 0.55
    static let agg4T: Double = 75
    static let agg4P: Double = 0.75
    static let agg5T: Double = 85
    static let agg5P: Double = 0.90
    static let agg6T: Double = 95
    static let agg6P: Double = 1.0

    // Max Cooling control-point temperatures (C) and fan percents (0 to 1).
    static let max0T: Double = 20
    static let max0P: Double = 0.10
    static let max1T: Double = 40
    static let max1P: Double = 0.20
    static let max2T: Double = 55
    static let max2P: Double = 0.60
    static let max3T: Double = 70
    static let max3P: Double = 1.0
    static let max4T: Double = 100
    static let max4P: Double = 1.0

    /// Balanced: gentle ramp from 55 C to full at 100 C.
    static let balanced: [(temp: Double, percent: Double)] = [
        (bal0T, bal0P), (bal1T, bal1P), (bal2T, bal2P), (bal3T, bal3P),
        (bal4T, bal4P), (bal5T, bal5P), (bal6T, bal6P), (bal7T, bal7P),
    ]

    /// Apple Silent: flat baseline until ~88 C, then sharp ramp to 100 C.
    static let appleSilent: [(temp: Double, percent: Double)] = [
        (sil0T, sil0P), (sil1T, sil1P), (sil2T, sil2P),
        (sil3T, sil3P), (sil4T, sil4P), (sil5T, sil5P),
    ]

    /// Aggressive: early ramp starting at 45 C.
    static let aggressive: [(temp: Double, percent: Double)] = [
        (agg0T, agg0P), (agg1T, agg1P), (agg2T, agg2P), (agg3T, agg3P),
        (agg4T, agg4P), (agg5T, agg5P), (agg6T, agg6P),
    ]

    /// Max Cooling: full ramp between 40 and 70 C.
    static let maxCooling: [(temp: Double, percent: Double)] = [
        (max0T, max0P), (max1T, max1P), (max2T, max2P),
        (max3T, max3P), (max4T, max4P),
    ]
}

/// A named curve preset with its control points. Points are authored in
/// Celsius temperatures and 0 to 1 percent fan speeds.
struct CurvePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let points: [(temp: Double, percent: Double)]

    static func == (lhs: CurvePreset, rhs: CurvePreset) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    func curvePoints() -> [CurvePoint] {
        CurveColumns.normalize(
            points.map { CurvePoint(temperature: $0.temp, fanPercent: $0.percent) })
    }
}

enum CurvePresets {
    /// Our built-in default. Gentle ramp starting at 55 C, full at 100 C.
    static let balanced = CurvePreset(
        id: "balanced",
        name: L10n.tr("Balanced"),
        subtitle: L10n.tr("Quiet idle, steady ramp as temps climb."),
        points: CurvePresetPoints.balanced)

    /// Approximation of Apple Silicon's firmware auto behavior. On M-series
    /// Macs the firmware holds fans at baseline RPM essentially flat until
    /// roughly 85 C sustained, then ramps sharply toward 100 C. This is a
    /// visual reference, not a measurement. Real Apple behavior varies by
    /// chassis and chip.
    static let appleSilent = CurvePreset(
        id: "apple-silent",
        name: L10n.tr("Apple Silent"),
        subtitle: L10n.tr("Approximates Apple Auto. Baseline until ~85 C, then ramps."),
        points: CurvePresetPoints.appleSilent)

    /// Starts ramping early. Good for sustained workloads where you prefer
    /// cooler temps over quiet operation.
    static let aggressive = CurvePreset(
        id: "aggressive",
        name: L10n.tr("Aggressive"),
        subtitle: L10n.tr("Starts ramping at 45 C. Keeps temps lower."),
        points: CurvePresetPoints.aggressive)

    /// Fan pinned near max above a low threshold. Loud but maximum cooling.
    static let maxCooling = CurvePreset(
        id: "max-cooling",
        name: L10n.tr("Max Cooling"),
        subtitle: L10n.tr("Full ramp between 40 and 70 C."),
        points: CurvePresetPoints.maxCooling)

    static let all: [CurvePreset] = [balanced, appleSilent, aggressive, maxCooling]
}
