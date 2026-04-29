//
//  CurvePresets.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import Foundation

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
    points: [
      (20, 0.0), (50, 0.0), (55, 0.30), (65, 0.35),
      (75, 0.45), (85, 0.60), (95, 0.80), (100, 1.0),
    ])

  /// Approximation of Apple Silicon's firmware auto behavior. On M-series
  /// Macs the firmware holds fans at baseline RPM essentially flat until
  /// roughly 85 C sustained, then ramps sharply toward 100 C. This is a
  /// visual reference, not a measurement. Real Apple behavior varies by
  /// chassis and chip.
  static let appleSilent = CurvePreset(
    id: "apple-silent",
    name: L10n.tr("Apple Silent"),
    subtitle: L10n.tr("Approximates Apple Auto. Baseline until ~85 C, then ramps."),
    points: [
      (20, 0.0), (80, 0.0), (88, 0.10), (92, 0.30), (96, 0.60), (100, 1.0),
    ])

  /// Starts ramping early. Good for sustained workloads where you prefer
  /// cooler temps over quiet operation.
  static let aggressive = CurvePreset(
    id: "aggressive",
    name: L10n.tr("Aggressive"),
    subtitle: L10n.tr("Starts ramping at 45 C. Keeps temps lower."),
    points: [
      (20, 0.0), (45, 0.25), (55, 0.40), (65, 0.55),
      (75, 0.75), (85, 0.90), (95, 1.0),
    ])

  /// Fan pinned near max above a low threshold. Loud but maximum cooling.
  static let maxCooling = CurvePreset(
    id: "max-cooling",
    name: L10n.tr("Max Cooling"),
    subtitle: L10n.tr("Full ramp between 40 and 70 C."),
    points: [
      (20, 0.10), (40, 0.20), (55, 0.60), (70, 1.0), (100, 1.0),
    ])

  static let all: [CurvePreset] = [balanced, appleSilent, aggressive, maxCooling]
}
