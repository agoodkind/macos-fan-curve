//
//  SystemHelperFirstInstallTests.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-09-07.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

final class SystemHelperFirstInstallTests: XCTestCase {
  @MainActor
  func testForcedRepairRegistersNotFoundHelper() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .unreachable,
      serviceStatus: .notFound
    )

    let state = await harness.reconcile(.forcedRepair)

    expect(state) == .running(active: harness.bundledIdentity)
    expect(harness.service.status) == .enabled
    expect(harness.service.registrationGeneration) == 1
    expect(harness.service.registerAttemptCount) == 1
    expect(harness.service.unregisterCount) == 0
    expect(harness.hardware.resetCount) == 0
    expect(harness.gate.isPaused) == false
  }

  @MainActor
  func testNotFoundHelperWaitsForExplicitRepair() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .unreachable,
      serviceStatus: .notFound
    )

    let startupState = await harness.reconcile(.startup)
    let reconnectState = await harness.reconcile(.reconnect)

    expect(startupState) == .unavailable(reason: "System Helper is not registered")
    expect(reconnectState) == startupState
    expect(harness.service.status) == .notFound
    expect(harness.service.hasRegistration) == false
    expect(harness.service.registerAttemptCount) == 0
    expect(harness.service.unregisterCount) == 0
    expect(harness.hardware.identityRequestCount) == 0
    expect(harness.hardware.resetCount) == 0
    expect(harness.gate.isPaused) == true
  }

  @MainActor
  func testNotFoundHelperWithMissingArtifactFailsBeforeRegistration() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .unreachable,
      serviceStatus: .notFound
    )
    try FileManager.default.removeItem(at: harness.bundledExecutableURL)

    let state = await harness.reconcile(.forcedRepair)

    expect(self.failureStage(of: state)) == .preflight
    expect(harness.service.status) == .notFound
    expect(harness.service.registerAttemptCount) == 0
    expect(harness.service.unregisterCount) == 0
    expect(harness.hardware.identityRequestCount) == 0
    expect(harness.hardware.resetCount) == 0
    expect(harness.gate.isPaused) == true
  }

  @MainActor
  func testNotFoundHelperRegistrationWaitsForApproval() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .unreachable,
      serviceStatus: .notFound,
      registerBehavior: .requiresApproval
    )

    let installState = await harness.reconcile(.forcedRepair)
    let startupState = await harness.reconcile(.startup)
    let retryState = await harness.reconcile(.forcedRepair)

    expect(installState) == .approvalRequired
    expect(startupState) == .approvalRequired
    expect(retryState) == .approvalRequired
    expect(harness.service.status) == .requiresApproval
    expect(harness.service.registerAttemptCount) == 1
    expect(harness.service.unregisterCount) == 0
    expect(harness.hardware.identityRequestCount) == 1
    expect(harness.hardware.resetCount) == 0
    expect(harness.gate.isPaused) == true
  }

  @MainActor
  func testNotFoundHelperWithMismatchedRegisteredIdentityKeepsControlPaused() async throws {
    let harness = try ReconcilerHarness(
      testCase: self,
      active: .unreachable,
      serviceStatus: .notFound,
      postRegisterIdentity: .outdated
    )

    let state = await harness.reconcile(.forcedRepair)

    expect(self.failureStage(of: state)) == .identityVerification
    expect(harness.service.status) == .enabled
    expect(harness.service.registerAttemptCount) == 1
    expect(harness.gate.isPaused) == true
  }

  private func failureStage(
    of state: SystemHelperRuntimeState
  ) -> SystemHelperFailureStage? {
    guard case .repairFailed(_, _, let failure) = state else { return nil }
    return failure.stage
  }
}
