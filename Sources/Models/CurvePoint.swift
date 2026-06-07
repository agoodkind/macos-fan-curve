//
//  CurvePoint.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

import Foundation

struct CurvePoint: Identifiable, Codable, Sendable, Equatable {
  let id: UUID
  var temperature: Double
  var fanPercent: Double

  init(temperature: Double, fanPercent: Double) {
    self.id = UUID()
    self.temperature = temperature
    self.fanPercent = fanPercent
  }
}
