//
//  AgentFanSnapshot.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

import Foundation

struct AgentFanSnapshot: Identifiable, Codable, Sendable, Equatable {
  var id: Int { index }

  let index: Int
  let actualRPM: Float
  let targetRPM: Float
  let minRPM: Float
  let maxRPM: Float
  let manualMode: Bool
}
