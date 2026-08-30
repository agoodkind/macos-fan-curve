//
//  FanCommandMapping.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-05-02.
//  Copyright © 2026, all rights reserved.
//

import Foundation

struct FanCommandMapping {
  let overdriveEnabled: Bool
  let underdriveEnabled: Bool
  let overdriveTargetRPM: Float

  func command(percent: Double, minRPM: Float, maxRPM: Float) -> FanCommand {
    if percent <= 0 {
      return .setRPM(underdriveEnabled ? 0 : minRPM)
    }

    let effectiveMax = overdriveEnabled ? max(maxRPM, overdriveTargetRPM) : maxRPM
    let effectiveMin: Float = underdriveEnabled ? 0 : minRPM
    let rpm = effectiveMin + Float(percent) * (effectiveMax - effectiveMin)
    return .setRPM(rpm)
  }
}
