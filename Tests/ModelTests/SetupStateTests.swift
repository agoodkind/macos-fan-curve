//
//  SetupStateTests.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-06-14.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class SetupStateTests: XCTestCase {
  func testRegistrationRepairRequiresHelperInstall() {
    let runtime = RuntimeState.resolve(
      RuntimeStateInputs(
        setup: RuntimeSetupInputs(backgroundAgent: .satisfied),
        systemHelper: .registrationNeedsRepair(reason: "missing registration"),
        snapshot: nil
      )
    )

    expect(runtime.setup) == .helperRequired(action: .installHelper)
  }

  func testMissingAgentTakesPrecedenceOverHelperApproval() {
    let runtime = RuntimeState.resolve(
      RuntimeStateInputs(
        setup: RuntimeSetupInputs(backgroundAgent: .required),
        systemHelper: .approvalRequired,
        snapshot: nil
      )
    )

    expect(runtime.setup) == .backgroundAgentRequired(action: .enableBackgroundAgent)
  }

  func testRunningHelperAndInstalledAgentAreReady() {
    let runtime = RuntimeState.resolve(
      RuntimeStateInputs(
        setup: RuntimeSetupInputs(backgroundAgent: .satisfied),
        systemHelper: .running(active: identity),
        snapshot: nil
      )
    )

    expect(runtime.setup) == .ready
  }

  func testCheckingHelperDoesNotRequestInstallation() {
    let runtime = RuntimeState.resolve(
      RuntimeStateInputs(
        setup: RuntimeSetupInputs(backgroundAgent: .satisfied),
        systemHelper: .checking,
        snapshot: nil
      )
    )

    expect(runtime.setup) == .ready
    expect(runtime.systemHelper) == .checking
  }

  func testActiveIdentitySurvivesStatesThatHaveAnActiveHelper() {
    let states: [SystemHelperRuntimeState] = [
      .running(active: identity),
      .updating(active: identity, bundled: identity),
      .outdated(active: identity, bundled: identity),
      .repairFailed(active: identity, bundled: identity, failure: failure),
    ]

    for state in states {
      expect(state.activeIdentity) == self.identity
    }
    expect(SystemHelperRuntimeState.checking.activeIdentity) == nil
  }

  func testOnlyRunningHelperPermitsFanControl() {
    let blockedStates: [SystemHelperRuntimeState] = [
      .checking,
      .updating(active: identity, bundled: identity),
      .outdated(active: identity, bundled: identity),
      .registrationNeedsRepair(reason: "missing registration"),
      .approvalRequired,
      .repairFailed(active: identity, bundled: identity, failure: failure),
      .unavailable(reason: "unreachable"),
    ]

    expect(SystemHelperRuntimeState.running(active: self.identity).permitsFanControl) == true
    for state in blockedStates {
      expect(state.permitsFanControl) == false
    }
  }

  func testStaleHealthRejectsFreshTelemetryPresentation() {
    expect(RuntimeHealth.stale.permitsFreshTelemetry) == false
  }

  func testOwnershipPreemptionKeepsTelemetryCurrent() {
    expect(RuntimeHealth.ownershipPreempted.permitsFreshTelemetry) == true
  }

  private let identity = SystemHelperIdentity(
    version: "0.4.0",
    build: "1",
    commit: "commit",
    executableHash: "hash",
    protocolVersion: 1
  )

  private let failure = SystemHelperFailure(
    operation: .automaticUpdate,
    stage: .register,
    reason: "registration failed",
    recovery: "Retry repair"
  )
}
