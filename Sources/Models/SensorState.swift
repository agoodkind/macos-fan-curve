//
//  SensorState.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026, all rights reserved.
//

import Combine
import Foundation

struct FanReading: Identifiable, Sendable {
  let id: Int
  let actualRPM: Float
  let minRPM: Float
  let maxRPM: Float
}

class SensorState: ObservableObject {
  @Published var governingTemperature: Double = 0
  @Published var fans: [FanReading] = []
  @Published var lastUpdate: Date?
}
