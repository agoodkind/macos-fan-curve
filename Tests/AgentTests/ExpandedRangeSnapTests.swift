//
//  ExpandedRangeSnapTests.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-08-13.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

private let curveRPM: Float = 4_000
private let underdriveRPM: Float = 3_000
private let standardMaximumRPM: Float = 6_000
private let overdriveMaximumRPM: Float = 10_000

private struct ExpandedRangeTransitionCase {
  let boostEnabled: Bool
  let previousState: ExpandedRangeState
  let nextState: ExpandedRangeState
  let previousRPM: Float
  let nextRPM: Float
}

private let expandedRangeTransitionCases = [
  ExpandedRangeTransitionCase(
    boostEnabled: false,
    previousState: ExpandedRangeState(overdriveEnabled: false, underdriveEnabled: false),
    nextState: ExpandedRangeState(overdriveEnabled: true, underdriveEnabled: false),
    previousRPM: curveRPM,
    nextRPM: standardMaximumRPM
  ),
  ExpandedRangeTransitionCase(
    boostEnabled: false,
    previousState: ExpandedRangeState(overdriveEnabled: true, underdriveEnabled: false),
    nextState: ExpandedRangeState(overdriveEnabled: false, underdriveEnabled: false),
    previousRPM: standardMaximumRPM,
    nextRPM: curveRPM
  ),
  ExpandedRangeTransitionCase(
    boostEnabled: false,
    previousState: ExpandedRangeState(overdriveEnabled: false, underdriveEnabled: false),
    nextState: ExpandedRangeState(overdriveEnabled: false, underdriveEnabled: true),
    previousRPM: curveRPM,
    nextRPM: underdriveRPM
  ),
  ExpandedRangeTransitionCase(
    boostEnabled: false,
    previousState: ExpandedRangeState(overdriveEnabled: false, underdriveEnabled: true),
    nextState: ExpandedRangeState(overdriveEnabled: false, underdriveEnabled: false),
    previousRPM: underdriveRPM,
    nextRPM: curveRPM
  ),
  ExpandedRangeTransitionCase(
    boostEnabled: true,
    previousState: ExpandedRangeState(overdriveEnabled: false, underdriveEnabled: false),
    nextState: ExpandedRangeState(overdriveEnabled: true, underdriveEnabled: false),
    previousRPM: standardMaximumRPM,
    nextRPM: overdriveMaximumRPM
  ),
  ExpandedRangeTransitionCase(
    boostEnabled: true,
    previousState: ExpandedRangeState(overdriveEnabled: true, underdriveEnabled: false),
    nextState: ExpandedRangeState(overdriveEnabled: false, underdriveEnabled: false),
    previousRPM: overdriveMaximumRPM,
    nextRPM: standardMaximumRPM
  ),
  ExpandedRangeTransitionCase(
    boostEnabled: true,
    previousState: ExpandedRangeState(overdriveEnabled: false, underdriveEnabled: false),
    nextState: ExpandedRangeState(overdriveEnabled: false, underdriveEnabled: true),
    previousRPM: curveRPM,
    nextRPM: standardMaximumRPM
  ),
  ExpandedRangeTransitionCase(
    boostEnabled: true,
    previousState: ExpandedRangeState(overdriveEnabled: false, underdriveEnabled: true),
    nextState: ExpandedRangeState(overdriveEnabled: false, underdriveEnabled: false),
    previousRPM: curveRPM,
    nextRPM: standardMaximumRPM
  ),
]

// MARK: - ExpandedRangeSnapTests

final class ExpandedRangeSnapTests: XCTestCase {
  func testTransitionsSnapTheNextCommandToTheCurveTarget() throws {
    for transition in expandedRangeTransitionCases {
      try expectTransitionToSnap(transition)
    }
  }

  private func expectTransitionToSnap(_ transition: ExpandedRangeTransitionCase) throws {
    let suiteName = "io.goodkind.fancurve.expanded-range-tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    set(transition.previousState, in: defaults)
    defaults.set(transition.boostEnabled, forKey: SharedConfigKeys.boostEnabled)

    let controller = AgentController(
      fanHardware: RecordingFanHardware(),
      sharedConfig: SharedConfig(defaults: defaults)
    )
    let telemetry = activeTelemetry()
    _ = controller.makeActiveTickContext(from: telemetry)
    set(transition.nextState, in: defaults)
    _ = controller.makeActiveTickContext(from: telemetry)

    let now = Date()
    controller.rampStateByFan[0] = RampCommandState(
      rpm: transition.previousRPM,
      timestamp: now
    )
    let command = controller.rampGovernedCommand(
      input: rampInput(for: transition, at: now)
    )

    guard case .setRPM(let commandedRPM) = command else {
      fail("Expanded range transition returned Auto")
      return
    }
    expect(commandedRPM) == transition.nextRPM
  }

  private func set(_ state: ExpandedRangeState, in defaults: UserDefaults) {
    defaults.set(state.overdriveEnabled, forKey: SharedConfigKeys.overdriveEnabled)
    defaults.set(state.underdriveEnabled, forKey: SharedConfigKeys.underdriveEnabled)
  }

  private func activeTelemetry() -> AgentControllerTickTypes.TickTelemetry {
    AgentControllerTickTypes.TickTelemetry(
      active: true,
      result: FanHardwareBatchRead(fans: [], temps: [:]),
      transitioned: false,
      maxCPUTemp: 70,
      cpuLoad: 0,
      gpuLoad: 0
    )
  }

  private func rampInput(
    for transition: ExpandedRangeTransitionCase,
    at now: Date
  ) -> RampCommandInput {
    RampCommandInput(
      command: .setRPM(transition.nextRPM),
      index: 0,
      currentFan: FanInfo(
        actualRPM: transition.previousRPM,
        targetRPM: transition.previousRPM,
        minRPM: 2_000,
        maxRPM: 6_000,
        manualMode: true
      ),
      currentTemperatureC: 70,
      fastTrendCPerTick: 0,
      slowTrendCPerTick: 0,
      fanResponseMultiplier: FanResponseMultiplier(1),
      now: now
    )
  }
}
