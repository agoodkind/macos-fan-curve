//
//  AgentController+StateReset.swift
//  FanCurveAgent
//
//  Created by Codex <noreply@openai.com> on 2026-08-13.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - AgentController

extension AgentController {
  func resetInactiveControllerState() {
    resetThermalControllerState()
    rampSnapRequested = false
    lastCurveShape = nil
    resetUserControlObservations()
  }

  func resetTemperatureUnavailableControllerState() {
    resetThermalControllerState()
  }

  private func resetThermalControllerState() {
    filteredTemperatureFast = nil
    filteredTemperatureSlow = nil
    previousFastTemperature = nil
    previousSlowTemperature = nil
    rampStateByFan.removeAll()
    lastCommandLogPercentByFan.removeAll()
    conditionedDemandPercent = nil
    conditionedDemandPercentVelocity = 0
    conditionedDemandTemperatureC = nil
    conditionedDemandTemperatureVelocityC = 0
    lastDemandConditioningTime = nil
    controllerMode = .holding
    thermalDebt = 0
  }
}
