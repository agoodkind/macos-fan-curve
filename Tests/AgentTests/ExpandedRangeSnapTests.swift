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

private let curvePercent = 0.5
private let testTemperature = 70.0
private let firstFanMinimumRPM: Float = 2_000
private let firstFanMaximumRPM: Float = 6_000
private let secondFanMinimumRPM: Float = 1_000
private let secondFanMaximumRPM: Float = 5_000
private let dampedStartingRPM: Float = 2_500
private let boostDampedStartingRPM: Float = 4_000
private let testOverdriveTargetRPM: Float = 10_000
private let standardCurveRPMs = [
  firstFanMinimumRPM + Float(curvePercent) * (firstFanMaximumRPM - firstFanMinimumRPM),
  secondFanMinimumRPM + Float(curvePercent) * (secondFanMaximumRPM - secondFanMinimumRPM),
]
private let overdriveCurveRPMs = [
  firstFanMinimumRPM + Float(curvePercent) * (testOverdriveTargetRPM - firstFanMinimumRPM),
  secondFanMinimumRPM + Float(curvePercent) * (testOverdriveTargetRPM - secondFanMinimumRPM),
]
private let underdriveCurveRPMs = [
  Float(curvePercent) * firstFanMaximumRPM,
  Float(curvePercent) * secondFanMaximumRPM,
]
private let standardBoostRPMs = [firstFanMaximumRPM, secondFanMaximumRPM]
private let overdriveBoostRPMs = [testOverdriveTargetRPM, testOverdriveTargetRPM]

private struct ExpandedRangeTransitionCase {
  let boostEnabled: Bool
  let previousState: ExpandedRangeState
  let nextState: ExpandedRangeState
  let expectedRPMs: [Float]
}

private let standardState = ExpandedRangeState(
  overdriveEnabled: false,
  underdriveEnabled: false
)
private let overdriveState = ExpandedRangeState(
  overdriveEnabled: true,
  underdriveEnabled: false
)
private let underdriveState = ExpandedRangeState(
  overdriveEnabled: false,
  underdriveEnabled: true
)

private let expandedRangeTransitionCases = [
  ExpandedRangeTransitionCase(
    boostEnabled: false,
    previousState: standardState,
    nextState: overdriveState,
    expectedRPMs: overdriveCurveRPMs
  ),
  ExpandedRangeTransitionCase(
    boostEnabled: false,
    previousState: overdriveState,
    nextState: standardState,
    expectedRPMs: standardCurveRPMs
  ),
  ExpandedRangeTransitionCase(
    boostEnabled: false,
    previousState: standardState,
    nextState: underdriveState,
    expectedRPMs: underdriveCurveRPMs
  ),
  ExpandedRangeTransitionCase(
    boostEnabled: false,
    previousState: underdriveState,
    nextState: standardState,
    expectedRPMs: standardCurveRPMs
  ),
  ExpandedRangeTransitionCase(
    boostEnabled: true,
    previousState: standardState,
    nextState: overdriveState,
    expectedRPMs: overdriveBoostRPMs
  ),
  ExpandedRangeTransitionCase(
    boostEnabled: true,
    previousState: overdriveState,
    nextState: standardState,
    expectedRPMs: standardBoostRPMs
  ),
  ExpandedRangeTransitionCase(
    boostEnabled: true,
    previousState: standardState,
    nextState: underdriveState,
    expectedRPMs: standardBoostRPMs
  ),
  ExpandedRangeTransitionCase(
    boostEnabled: true,
    previousState: underdriveState,
    nextState: standardState,
    expectedRPMs: standardBoostRPMs
  ),
]

// MARK: - ExpandedRangeSnapTests

final class ExpandedRangeSnapTests: XCTestCase {
  func testTransitionsSnapEveryFanToTheMappedCurveTarget() async throws {
    for transition in expandedRangeTransitionCases {
      try await expectTransitionToSnap(transition)
    }
  }

  func testFirstObservationDoesNotSnap() async throws {
    let fixture = try makeFixture(state: standardState, boostEnabled: false)
    fixture.controller.rampStateByFan = rampStates(
      fanCount: fixture.fanCount,
      rpm: dampedStartingRPM
    )

    await fixture.controller.tick()

    let commandedRPMs = fixture.hardware.latestAppliedRPMs
    expect(commandedRPMs).to(haveCount(fixture.fanCount))
    expect(commandedRPMs.first) < firstMappedStandardRPM
  }

  func testTransitionDuringTemperatureLossSnapsWhenTemperatureReturns() async throws {
    let fixture = try makeFixture(state: standardState, boostEnabled: false)
    await fixture.controller.tick()
    fixture.hardware.readResult = telemetry(fans: fixture.fans, temperature: nil)
    set(overdriveState, in: fixture.defaults)
    await fixture.controller.tick()
    fixture.hardware.readResult = telemetry(fans: fixture.fans, temperature: testTemperature)
    fixture.controller.rampStateByFan = rampStates(
      fanCount: fixture.fanCount,
      rpm: dampedStartingRPM
    )

    await fixture.controller.tick()

    expect(fixture.hardware.latestAppliedRPMs) == overdriveCurveRPMs
  }

  func testTransitionWithoutFansRemainsPendingUntilFansReturn() async throws {
    let fixture = try makeFixture(state: standardState, boostEnabled: false)
    await fixture.controller.tick()
    set(overdriveState, in: fixture.defaults)
    fixture.hardware.readResult = telemetry(fans: [], temperature: testTemperature)
    await fixture.controller.tick()
    fixture.hardware.readResult = telemetry(fans: fixture.fans, temperature: testTemperature)
    fixture.controller.rampStateByFan = rampStates(
      fanCount: fixture.fanCount,
      rpm: dampedStartingRPM
    )

    await fixture.controller.tick()

    expect(fixture.hardware.latestAppliedRPMs) == overdriveCurveRPMs
  }

  private var firstMappedStandardRPM: Float {
    firstFanMinimumRPM
      + Float(curvePercent) * (firstFanMaximumRPM - firstFanMinimumRPM)
  }

  private func expectTransitionToSnap(
    _ transition: ExpandedRangeTransitionCase
  ) async throws {
    let fixture = try makeFixture(
      state: transition.previousState,
      boostEnabled: transition.boostEnabled
    )
    await fixture.controller.tick()
    fixture.hardware.clearRequests()
    set(transition.nextState, in: fixture.defaults)
    let startingRPM = transition.boostEnabled ? boostDampedStartingRPM : dampedStartingRPM
    fixture.controller.rampStateByFan = rampStates(
      fanCount: fixture.fanCount,
      rpm: startingRPM
    )

    await fixture.controller.tick()

    expect(fixture.hardware.latestAppliedRPMs) == transition.expectedRPMs
  }

  private func makeFixture(
    state: ExpandedRangeState,
    boostEnabled: Bool
  ) throws -> ExpandedRangeFixture {
    let suiteName = "io.goodkind.fancurve.expanded-range-tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(true, forKey: SharedConfigKeys.curveActive)
    defaults.set(boostEnabled, forKey: SharedConfigKeys.boostEnabled)
    set(state, in: defaults)
    try setConstantCurve(in: defaults)

    let fans = testFans()
    let hardware = RecordingFanHardware(
      readResult: telemetry(fans: fans, temperature: testTemperature)
    )
    let controller = AgentController(
      fanHardware: hardware,
      sharedConfig: SharedConfig(defaults: defaults)
    )
    controller.lastActivityState = .active
    controller.sensorKeysResolved = true
    controller.tempKeys = ["TC0P"]
    controller.cpuTempKeys = ["TC0P"]
    addTeardownBlock {
      UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
    return ExpandedRangeFixture(
      controller: controller,
      hardware: hardware,
      defaults: defaults,
      fans: fans
    )
  }

  private func setConstantCurve(in defaults: UserDefaults) throws {
    let curve = [
      CurvePoint(temperature: 0, fanPercent: curvePercent),
      CurvePoint(temperature: 100, fanPercent: curvePercent),
    ]
    defaults.set(try JSONEncoder().encode(curve), forKey: SharedConfigKeys.curvePoints)
  }

  private func set(_ state: ExpandedRangeState, in defaults: UserDefaults) {
    defaults.set(state.overdriveEnabled, forKey: SharedConfigKeys.overdriveEnabled)
    defaults.set(state.underdriveEnabled, forKey: SharedConfigKeys.underdriveEnabled)
  }

  private func testFans() -> [FanInfo] {
    [
      fan(minimumRPM: firstFanMinimumRPM, maximumRPM: firstFanMaximumRPM),
      fan(minimumRPM: secondFanMinimumRPM, maximumRPM: secondFanMaximumRPM),
    ]
  }

  private func fan(minimumRPM: Float, maximumRPM: Float) -> FanInfo {
    FanInfo(
      actualRPM: dampedStartingRPM,
      targetRPM: dampedStartingRPM,
      minRPM: minimumRPM,
      maxRPM: maximumRPM,
      manualMode: true
    )
  }

  private func telemetry(
    fans: [FanInfo],
    temperature: Double?
  ) -> FanHardwareBatchRead {
    let temperatures = temperature.map { ["TC0P": Float($0)] } ?? [:]
    return FanHardwareBatchRead(fans: fans, temps: temperatures)
  }

  private func rampStates(fanCount: Int, rpm: Float) -> [UInt: RampCommandState] {
    var states: [UInt: RampCommandState] = [:]
    for fanIndex in 0..<fanCount {
      states[UInt(fanIndex)] = RampCommandState(rpm: rpm, timestamp: Date())
    }
    return states
  }
}

// MARK: - ExpandedRangeFixture

private struct ExpandedRangeFixture {
  let controller: AgentController
  let hardware: RecordingFanHardware
  let defaults: UserDefaults
  let fans: [FanInfo]

  var fanCount: Int { fans.count }
}
