//
//  SensorState.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import Foundation

struct SensorReading: Identifiable, Sendable {
  let id: String
  let name: String
  let group: String
  let value: Double
}

struct FanReading: Identifiable, Sendable {
  let id: Int
  let actualRPM: Float
  let targetRPM: Float
  let minRPM: Float
  let maxRPM: Float
  let manualMode: Bool
}

class SensorState: ObservableObject {
  @Published var governingTemperature: Double = 0
  @Published var temperatures: [SensorReading] = []
  @Published var fans: [FanReading] = []
  @Published var lastUpdate: Date?
}
