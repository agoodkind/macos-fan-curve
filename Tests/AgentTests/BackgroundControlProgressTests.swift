//
//  BackgroundControlProgressTests.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-09-12.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

@MainActor
final class BackgroundControlProgressTests: XCTestCase {
  func testInitialObservationHidesSetupButtonUntilRequiredSetupIsKnown() throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    let state = fixture.makeState()

    expect(state.backgroundControlProgress) == .connecting
    expect(state.setupActionTitle) == nil

    state.refreshOnce(agentClient: fixture.client)

    expect(state.backgroundControlProgress) == nil
    expect(state.setupActionTitle) == "Enable Background Control"
    expect(fixture.service.registerCount) == 0
  }

  func testCurrentAgentWaitsForAcceptedStateHeartbeatAndFirstSample() throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.connectionGeneration = 1
    fixture.client.helperState = .running(active: fixture.identity)
    let state = fixture.makeState()

    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == .connecting
    expect(state.setupActionTitle) == nil

    fixture.client.runtimeStateGeneration = 1
    fixture.client.snapshot = snapshot()
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == .connecting

    fixture.client.snapshot = nil
    publishCurrentAgentIdentity(fixture)
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == .connecting

    fixture.client.snapshot = snapshot()
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == nil
    expect(fixture.service.registerCount) == 0
  }

  func testOldReadyAgentStaysUpdatingUntilReplacementStateIsCurrentAndFresh() throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.connectionGeneration = 1
    fixture.client.runtimeStateGeneration = 1
    fixture.client.helperState = .running(active: fixture.identity)
    fixture.client.snapshot = snapshot()
    fixture.defaults.set("old-agent", forKey: SharedConfigKeys.agentExecutableHash)
    fixture.defaults.set(Date().timeIntervalSince1970, forKey: SharedConfigKeys.agentLastTick)
    let state = fixture.makeState()

    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == .updating
    expect(state.setupActionTitle) == nil
    expect(fixture.service.registerCount) == 1

    publishCurrentAgentIdentity(fixture)
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == .updating

    fixture.client.connectionGeneration = 2
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == .updating

    fixture.client.runtimeStateGeneration = 2
    fixture.client.helperState = .updating(active: fixture.identity, bundled: fixture.identity)
    fixture.client.snapshot = nil
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == .updating

    fixture.client.helperState = .running(active: fixture.identity)
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == .updating

    fixture.client.snapshot = snapshot()
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == nil
    expect(state.backgroundControlRetiringGeneration) == nil
    expect(fixture.service.registerCount) == 1
  }

  func testHelperApprovalAndFailureRemainVisibleWithoutHeartbeat() throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.connectionGeneration = 1
    fixture.client.runtimeStateGeneration = 1
    fixture.client.helperState = .approvalRequired
    let state = fixture.makeState()

    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == nil
    expect(state.setupActionTitle) == "Open System Settings"

    fixture.client.helperState = .unavailable(reason: "Helper failed")
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == nil
    expect(state.step) == .helperMissing

    state.failSetup("Registration rejected")
    expect(state.backgroundControlProgress) == nil
    expect(state.setupActionTitle) == "Retry Setup"
  }

  func testAgentApprovalAndExplicitDisableDoNotShowConnecting() throws {
    let fixture = try GuidedSetupFixture()
    defer { fixture.cleanUp() }
    fixture.service.registrationStatus = .requiresApproval
    let state = fixture.makeState()

    state.beginSetup(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == nil
    expect(state.setupActionTitle) == "Open System Settings"

    state.unregisterAgent()
    expect(state.backgroundControlProgress) == nil
    expect(state.setupProgress) == .cancelled
  }

  func testMissingFirstSampleStopsConnectingAfterExistingStartupGrace() throws {
    let fixture = try readyServiceFixture()
    defer { fixture.cleanUp() }
    let state = fixture.makeState()

    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == .connecting

    state.backgroundControlSampleWaitStartedAt = .distantPast
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == nil
    expect(fixture.client.runtimeState.health) == .degraded(reason: .snapshotUnavailable)
  }

  func testTelemetryWaitsForAUsableFirstSampleBeforeShowingTheDashboard() throws {
    let fixture = try readyServiceFixture()
    defer { fixture.cleanUp() }
    let state = fixture.makeState()
    fixture.client.snapshot = snapshot(timestamp: .distantPast)

    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == .connecting
    expect(fixture.client.runtimeState.health) == .stale

    fixture.client.snapshot = snapshot(fans: [])
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == .connecting

    fixture.client.snapshot = snapshot(governingTemperatureC: 0)
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == .connecting

    fixture.client.snapshot = snapshot()
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == nil
  }

  func testPersistentTelemetryFailureStopsConnectingAfterStartupGrace() throws {
    let fixture = try readyServiceFixture()
    defer { fixture.cleanUp() }
    let state = fixture.makeState()
    fixture.client.snapshot = snapshot(timestamp: .distantPast)

    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == .connecting

    state.backgroundControlSampleWaitStartedAt = .distantPast
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == nil
    expect(fixture.client.runtimeState.health) == .stale

    fixture.client.snapshot = snapshot(helperReachable: false)
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == nil
    expect(fixture.client.runtimeState.health) == .degraded(reason: .helperUnavailable)
  }

  func testTelemetryLossAfterStartupKeepsTheDashboardVisible() throws {
    let fixture = try readyServiceFixture()
    defer { fixture.cleanUp() }
    let state = fixture.makeState()
    fixture.client.snapshot = snapshot()

    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == nil

    fixture.client.snapshot = snapshot(timestamp: .distantPast)
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == nil
    expect(fixture.client.runtimeState.health) == .stale

    fixture.client.snapshot = nil
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == nil
    expect(fixture.client.runtimeState.health) == .degraded(reason: .snapshotUnavailable)
  }

  func testHelperUpdateRequiresTelemetryPublishedAfterReplacementBegan() throws {
    let fixture = try readyServiceFixture()
    defer { fixture.cleanUp() }
    let state = fixture.makeState()
    let retainedSnapshot = snapshot()
    fixture.client.snapshot = retainedSnapshot

    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == nil

    fixture.client.helperState = .updating(active: fixture.identity, bundled: fixture.identity)
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == .updating

    fixture.client.helperState = .running(active: fixture.identity)
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == .updating

    let updateStartedAt = try XCTUnwrap(state.backgroundControlUpdateStartedAt)
    fixture.client.snapshot = snapshot(timestamp: updateStartedAt.addingTimeInterval(1))
    state.refreshOnce(agentClient: fixture.client)
    expect(state.backgroundControlProgress) == nil
  }

  private func readyServiceFixture() throws -> GuidedSetupFixture {
    let fixture = try GuidedSetupFixture()
    fixture.service.status = .enabled
    fixture.client.connectionState = .connected
    fixture.client.connectionGeneration = 1
    fixture.client.runtimeStateGeneration = 1
    fixture.client.helperState = .running(active: fixture.identity)
    publishCurrentAgentIdentity(fixture)
    return fixture
  }

  private func publishCurrentAgentIdentity(_ fixture: GuidedSetupFixture) {
    fixture.defaults.set("bundled-agent", forKey: SharedConfigKeys.agentExecutableHash)
    fixture.defaults.set(Date().timeIntervalSince1970, forKey: SharedConfigKeys.agentLastTick)
  }

  private func snapshot(
    timestamp: Date = Date(),
    helperReachable: Bool = true,
    governingTemperatureC: Double = 50,
    fans: [AgentFanSnapshot] = [
      AgentFanSnapshot(
        index: 0,
        actualRPM: 2_400,
        targetRPM: 2_600,
        minRPM: 1_200,
        maxRPM: 5_800,
        manualMode: false
      )
    ]
  ) -> AgentSnapshot {
    AgentSnapshot(
      timestamp: timestamp,
      helperReachable: helperReachable,
      curveActive: false,
      boostEnabled: false,
      governingTemperatureC: governingTemperatureC,
      committedTemperatureC: 50,
      rawPressureTemperatureC: 50,
      cpuLoadPercent: 10,
      gpuLoadPercent: 10,
      effectiveCurvePercent: 0,
      baseCurvePercent: 0,
      rawBaselinePercent: 0,
      semanticDemandPercent: 0,
      thermalDemandSource: .curve,
      semanticDemandTemperatureC: 50,
      commandedTargetPercent: 0,
      commandedTargetTemperatureC: nil,
      committedPercent: 0,
      controllerMode: .holding,
      bandIndex: 0,
      holdRemainingSeconds: 0,
      assistFloorPercent: nil,
      activeAssistKinds: [],
      fans: fans
    )
  }
}
