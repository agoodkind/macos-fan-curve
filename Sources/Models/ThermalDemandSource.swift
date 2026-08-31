//
//  ThermalDemandSource.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-05-01.
//  Copyright © 2026, all rights reserved.
//

import Foundation

enum ThermalDemandSource: String, Codable, Sendable, Equatable {
  case assist
  case boost
  case curve
}
