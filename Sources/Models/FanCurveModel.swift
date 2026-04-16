//
//  FanCurveModel.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

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

class FanCurveModel: ObservableObject {
  @Published var controlPoints: [CurvePoint]
  @Published var interpolationMode: InterpolationMode
  @Published var isActive: Bool

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
    self.isActive = false
  }

  func evaluate(at temperature: Double) -> Double {
    CurveInterpolation.evaluate(at: temperature, points: controlPoints, mode: interpolationMode)
  }

  func rpmForFan(percent: Double, minRPM: Float, maxRPM: Float) -> Float {
    if percent <= 0 { return 0 }
    return minRPM + Float(percent) * (maxRPM - minRPM)
  }

  func resetToDefault() {
    controlPoints = Self.defaultCurve
    save()
  }

  func save() {
    if let data = try? JSONEncoder().encode(controlPoints) {
      UserDefaults.standard.set(data, forKey: "fanCurvePoints")
    }
    UserDefaults.standard.set(interpolationMode.rawValue, forKey: "interpolationMode")
  }

  private static func load() -> [CurvePoint]? {
    guard let data = UserDefaults.standard.data(forKey: "fanCurvePoints"),
      let points = try? JSONDecoder().decode([CurvePoint].self, from: data),
      points.count >= 2
    else { return nil }
    return points
  }

  private static func loadMode() -> InterpolationMode {
    guard let raw = UserDefaults.standard.string(forKey: "interpolationMode"),
      let mode = InterpolationMode(rawValue: raw)
    else { return .linear }
    return mode
  }
}
