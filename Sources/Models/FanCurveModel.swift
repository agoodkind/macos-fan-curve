//
//  FanCurveModel.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import Combine
import Foundation

/// Conservative default for Overdrive's 100% target when no probe result
/// has been written yet. Firmware accepts it on M4 Max and M5 Max.
private let overdriveTargetRPMDefault: Float = 10000

/// When Overdrive is on, 100% on the curve maps to this value. Prefers
/// the measured value from a Learn probe, falling back to the default.
var overdriveTargetRPM: Float {
  let measured = Float(
    sharedDefaults().double(forKey: SharedConfigKeys.overdriveTargetRPMMeasured))
  return measured > 0 ? measured : overdriveTargetRPMDefault
}

/// Map a curve percent (0...1) to a command for a fan given its reported
/// min/max RPM. Honors the Overdrive and Underdrive settings read from the
/// shared UserDefaults suite so the GUI and the Agent agree.
///
/// Semantics:
/// - percent <= 0 with underdrive off: fan goes to auto.
/// - percent <= 0 with underdrive on: fan is forced to 0 RPM in manual mode.
/// - percent > 0 with overdrive off: interpolate between minRPM and maxRPM.
/// - percent > 0 with overdrive on: interpolate between minRPM and overdriveTargetRPM.
/// - Underdrive also lowers the floor from minRPM to 0 for above-zero targets.
func fanCommandFor(percent: Double, minRPM: Float, maxRPM: Float) -> FanCommand {
  let defaults = sharedDefaults()
  let overdrive = defaults.bool(forKey: SharedConfigKeys.overdriveEnabled)
  let underdrive = defaults.bool(forKey: SharedConfigKeys.underdriveEnabled)

  if percent <= 0 {
    return underdrive ? .setRPM(0) : .auto
  }
  let effectiveMax = overdrive ? max(maxRPM, overdriveTargetRPM) : maxRPM
  let effectiveMin: Float = underdrive ? 0 : minRPM
  let rpm = effectiveMin + Float(percent) * (effectiveMax - effectiveMin)
  return .setRPM(rpm)
}

/// Access the shared UserDefaults suite used by GUI + Agent.
/// Persists to ~/Library/Preferences/<SHARED_SUITE_ID>.plist
func sharedDefaults() -> UserDefaults {
  UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
}

class FanCurveModel: ObservableObject {
  @Published var controlPoints: [CurvePoint] {
    didSet { save() }
  }
  @Published var interpolationMode: InterpolationMode {
    didSet { save() }
  }
  @Published var isActive: Bool {
    didSet {
      sharedDefaults().set(isActive, forKey: SharedConfigKeys.curveActive)
    }
  }

  /// Ships as the Apple Silent approximation so a fresh install matches
  /// roughly what macOS would do on its own. The user can pick a more
  /// aggressive preset from Settings if they want.
  static let defaultCurve: [CurvePoint] = CurvePresets.appleSilent.curvePoints()

  static let tempRange: ClosedRange<Double> = 20...110

  init() {
    let loaded = Self.load() ?? Self.defaultCurve
    self.controlPoints = Self.normalizedCurve(loaded)
    self.interpolationMode = Self.loadMode()
    self.isActive = sharedDefaults().bool(forKey: SharedConfigKeys.curveActive)
  }

  /// Ensures the curve has an explicit grabber at the plot's left edge
  /// so the user can always drag the starting fan percent directly. If
  /// the first stored point already sits at or below tempRange.lowerBound,
  /// returns the curve unchanged.
  private static func normalizedCurve(_ points: [CurvePoint]) -> [CurvePoint] {
    guard let first = points.first else { return points }
    if first.temperature <= tempRange.lowerBound { return points }
    var updated = points
    updated.insert(
      CurvePoint(temperature: tempRange.lowerBound, fanPercent: first.fanPercent),
      at: 0)
    return updated
  }

  func evaluate(at temperature: Double) -> Double {
    CurveInterpolation.evaluate(at: temperature, points: controlPoints, mode: interpolationMode)
  }

  /// Map a curve percent (0...1) to an RPM target for a specific fan.
  /// Shares its semantics with `fanCommandFor`. Kept for GUI preview uses.
  func rpmForFan(percent: Double, minRPM: Float, maxRPM: Float) -> Float {
    switch fanCommandFor(percent: percent, minRPM: minRPM, maxRPM: maxRPM) {
    case .auto: return 0
    case .setRPM(let rpm): return rpm
    }
  }

  func resetToDefault() {
    controlPoints = Self.defaultCurve
  }

  func save() {
    let defaults = sharedDefaults()
    if let data = try? JSONEncoder().encode(controlPoints) {
      defaults.set(data, forKey: SharedConfigKeys.curvePoints)
    }
    defaults.set(interpolationMode.rawValue, forKey: SharedConfigKeys.interpolationMode)
  }

  private static func load() -> [CurvePoint]? {
    guard let data = sharedDefaults().data(forKey: SharedConfigKeys.curvePoints),
      let points = try? JSONDecoder().decode([CurvePoint].self, from: data),
      points.count >= 2
    else { return nil }
    return points
  }

  private static func loadMode() -> InterpolationMode {
    guard let raw = sharedDefaults().string(forKey: SharedConfigKeys.interpolationMode),
      let mode = InterpolationMode(rawValue: raw)
    else { return .catmullRom }
    return mode
  }
}
