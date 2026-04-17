//
//  FanCurveModel.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import Combine
import Foundation

struct CurvePoint: Identifiable, Codable, Sendable {
  let id: UUID
  var temperature: Double
  var fanPercent: Double

  init(temperature: Double, fanPercent: Double) {
    self.id = UUID()
    self.temperature = temperature
    self.fanPercent = fanPercent
  }
}

enum InterpolationMode: String, Codable, Sendable {
  case linear
  case catmullRom
}

/// Shared UserDefaults keys. Both GUI and Agent read/write via the shared suite.
enum SharedConfigKeys {
  static let curvePoints = "curvePoints"
  static let interpolationMode = "interpolationMode"
  static let curveActive = "curveActive"
  static let overdriveEnabled = "overdriveEnabled"
  static let agentPID = "agentPID"
  static let agentLastTick = "agentLastTick"
}

/// When Overdrive is on, 100% on the curve maps to this value instead of the
/// firmware reported max. Firmware accepts it and the fan spins to its
/// physical limit. Verified on M4 Max and M5 Max.
let overdriveTargetRPM: Float = 10000

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

  static let defaultCurve: [CurvePoint] = [
    CurvePoint(temperature: 30, fanPercent: 0.0),
    CurvePoint(temperature: 50, fanPercent: 0.0),
    CurvePoint(temperature: 55, fanPercent: 0.30),
    CurvePoint(temperature: 65, fanPercent: 0.35),
    CurvePoint(temperature: 75, fanPercent: 0.45),
    CurvePoint(temperature: 85, fanPercent: 0.60),
    CurvePoint(temperature: 95, fanPercent: 0.80),
    CurvePoint(temperature: 100, fanPercent: 1.0),
  ]

  static let tempRange: ClosedRange<Double> = 20...110

  init() {
    self.controlPoints = Self.load() ?? Self.defaultCurve
    self.interpolationMode = Self.loadMode()
    self.isActive = sharedDefaults().bool(forKey: SharedConfigKeys.curveActive)
  }

  func evaluate(at temperature: Double) -> Double {
    CurveInterpolation.evaluate(at: temperature, points: controlPoints, mode: interpolationMode)
  }

  /// Map a curve percent (0...1) to an RPM target for a specific fan.
  ///
  /// Zero percent writes zero so the helper can fall back to auto mode.
  /// Above zero we interpolate linearly between the fan's reported min and
  /// its effective max.
  ///
  /// When Overdrive is enabled in Settings, the effective max is the value
  /// of `overdriveTargetRPM` rather than the firmware reported max. The
  /// M5 Max firmware still accepts the higher target and spins the fan to
  /// its physical limit, well above the reported value.
  func rpmForFan(percent: Double, minRPM: Float, maxRPM: Float) -> Float {
    if percent <= 0 { return 0 }
    let overdriveOn = sharedDefaults().bool(forKey: SharedConfigKeys.overdriveEnabled)
    let effectiveMax = overdriveOn ? max(maxRPM, overdriveTargetRPM) : maxRPM
    return minRPM + Float(percent) * (effectiveMax - minRPM)
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
