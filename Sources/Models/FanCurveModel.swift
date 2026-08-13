//
//  FanCurveModel.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Combine
import Foundation

private let fanCurveModelLog = AppLog.make(category: "FanCurveModel")

private enum FanCurveModelConstants {
  static let minimumStoredCurvePoints: Int = 2
}

/// Conservative default for Overdrive's 100% target when no probe result
/// has been written yet. Firmware accepts it on M4 Max and M5 Max.
private let overdriveTargetRPMDefault: Float = 10_000

/// When Overdrive is on, 100% on the curve maps to this value. Prefers
/// the measured value from a Learn probe, falling back to the default.
var overdriveTargetRPM: Float {
  resolvedOverdriveTargetRPM(defaults: sharedDefaults())
}

func resolvedOverdriveTargetRPM(defaults: UserDefaults) -> Float {
  let measured = Float(defaults.double(forKey: SharedConfigKeys.overdriveTargetRPMMeasured))
  return measured > 0 ? measured : overdriveTargetRPMDefault
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

  init() {
    let loaded = Self.load()
    self.controlPoints = Self.normalizedCurve(loaded.isEmpty ? Self.defaultCurve : loaded)
    self.interpolationMode = Self.loadMode()
    self.isActive = sharedDefaults().bool(forKey: SharedConfigKeys.curveActive)
  }

  /// Re-samples any imported/saved curve onto the editor's fixed column grid
  /// so presets, learned curves, and legacy saved curves all behave the same.
  private static func normalizedCurve(_ points: [CurvePoint]) -> [CurvePoint] {
    CurveColumns.normalize(points)
  }

  func evaluate(at temperature: Double) -> Double {
    CurveInterpolation.evaluate(at: temperature, points: controlPoints, mode: interpolationMode)
  }

  func resetToDefault() {
    replaceCurve(Self.defaultCurve)
  }

  func replaceCurve(_ points: [CurvePoint]) {
    controlPoints = Self.normalizedCurve(points)
  }

  func save() {
    let defaults = sharedDefaults()
    do {
      let data = try JSONEncoder().encode(controlPoints)
      defaults.set(data, forKey: SharedConfigKeys.curvePoints)
    } catch {
      fanCurveModelLog.error(
        "curve.save.encode_failed error=\(error.localizedDescription, privacy: .public) recovery=skip-points-write"
      )
    }
    defaults.set(interpolationMode.rawValue, forKey: SharedConfigKeys.interpolationMode)
  }

  private static func load() -> [CurvePoint] {
    guard let data = sharedDefaults().data(forKey: SharedConfigKeys.curvePoints) else {
      return []
    }
    do {
      let points = try JSONDecoder().decode([CurvePoint].self, from: data)
      guard points.count >= FanCurveModelConstants.minimumStoredCurvePoints else {
        fanCurveModelLog.notice("curve.load.invalid reason=too-few-points recovery=default")
        return []
      }
      return points
    } catch {
      fanCurveModelLog.notice(
        "curve.load.decode_failed error=\(error.localizedDescription, privacy: .public) recovery=default"
      )
      return []
    }
  }

  private static func loadMode() -> InterpolationMode {
    guard let raw = sharedDefaults().string(forKey: SharedConfigKeys.interpolationMode),
      let mode = InterpolationMode(rawValue: raw)
    else { return .catmullRom }
    return mode
  }
}
