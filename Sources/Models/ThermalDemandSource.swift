//
//  ThermalDemandSource.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-01.
//  Copyright © 2026
//

import Foundation

enum ThermalDemandSource: String, Codable, Sendable, Equatable {
    case curve
    case assist
    case boost
}
