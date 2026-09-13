//
//  TestControlXPCIntegrationTests+HelperApproval.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-09-07.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

@MainActor
extension TestControlXPCIntegrationTests {
  func testCurrentStateVerifiesNewHelperAfterApprovalWithoutAnotherInstall() async throws {
    let expectedIdentityRequestCount = 2
    let fixture = try ControlledSystemHelperLifecycleFixture(
      testCase: self,
      active: .unreachable,
      serviceStatus: .notFound,
      registerBehavior: .requiresApproval
    )
    let harness = try ControlledXPCHarness(lifecycleFixture: fixture)
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()

    let error = await captureError {
      try await harness.client.installOrRepairHelper()
    }
    let installRejected = error != nil
    expect(installRejected) == true
    try await harness.client.refreshCurrentState()
    expect(harness.client.runtimeState.systemHelper) == .approvalRequired
    expect(harness.controllerIsPaused) == true

    fixture.service.setStatus(.enabled)
    fixture.fanHardware.setIdentity(.identity(fixture.bundledIdentity))
    try await harness.client.refreshCurrentState()

    expect(harness.client.runtimeState.systemHelper)
      == .running(active: fixture.bundledIdentity)
    expect(harness.controllerIsPaused) == false
    expect(fixture.service.registerAttemptCount) == 1
    expect(fixture.service.unregisterCount) == 0
    expect(fixture.fanHardware.identityRequestCount) == expectedIdentityRequestCount

    try await harness.client.refreshCurrentState()
    expect(fixture.service.registerAttemptCount) == 1
    expect(fixture.fanHardware.identityRequestCount) == expectedIdentityRequestCount
  }

  func testCurrentStateResumesApprovedUpgradeWithoutReplacingItAgain() async throws {
    let fixture = try ControlledSystemHelperLifecycleFixture(
      testCase: self,
      active: .outdated,
      registerBehavior: .requiresApproval
    )
    let harness = try ControlledXPCHarness(lifecycleFixture: fixture)
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()

    let initialState = await harness.reconcile(.startup)
    expect(initialState) == .approvalRequired
    try await harness.client.refreshCurrentState()
    expect(harness.client.runtimeState.systemHelper) == .approvalRequired

    fixture.service.setStatus(.enabled)
    fixture.fanHardware.setIdentity(.identity(fixture.bundledIdentity))
    try await harness.client.refreshCurrentState()

    expect(harness.client.runtimeState.systemHelper)
      == .running(active: fixture.bundledIdentity)
    expect(harness.controllerIsPaused) == false
    expect(fixture.service.registerAttemptCount) == 1
    expect(fixture.service.unregisterCount) == 1
    expect(fixture.fanHardware.allFansAutomatic) == true
  }

  func testCurrentStateDoesNotTreatEnabledServiceAsVerifiedHelper() async throws {
    let fixture = try ControlledSystemHelperLifecycleFixture(
      testCase: self,
      active: .unreachable,
      serviceStatus: .requiresApproval
    )
    let harness = try ControlledXPCHarness(lifecycleFixture: fixture)
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()
    expect(harness.client.runtimeStateGeneration) == harness.client.connectionGeneration
    _ = await harness.reconcile(.startup)
    try await harness.client.refreshCurrentState()
    expect(harness.client.runtimeState.systemHelper) == .approvalRequired

    fixture.service.setStatus(.enabled)
    try await harness.client.refreshCurrentState()

    expect(harness.client.runtimeState.systemHelper.permitsFanControl) == false
    let requiresApproval = harness.client.runtimeState.systemHelper == .approvalRequired
    expect(requiresApproval) == false
    expect(harness.controllerIsPaused) == true
    expect(fixture.fanHardware.identityRequestCount) == 1
    expect(fixture.service.registerAttemptCount) == 0
    expect(fixture.service.unregisterCount) == 0
  }

  func testCurrentStateReportsRemovedApprovalRegistrationWithoutInstalling() async throws {
    let fixture = try ControlledSystemHelperLifecycleFixture(
      testCase: self,
      active: .unreachable,
      serviceStatus: .requiresApproval
    )
    let harness = try ControlledXPCHarness(lifecycleFixture: fixture)
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()
    _ = await harness.reconcile(.startup)
    try await harness.client.refreshCurrentState()
    expect(harness.client.runtimeState.systemHelper) == .approvalRequired

    fixture.service.setStatus(.notRegistered)
    try await harness.client.refreshCurrentState()

    expect(harness.client.runtimeState.systemHelper)
      == .registrationNeedsRepair(reason: "System Helper is not registered")
    expect(harness.controllerIsPaused) == true
    expect(fixture.fanHardware.identityRequestCount) == 0
    expect(fixture.service.registerAttemptCount) == 0
    expect(fixture.service.unregisterCount) == 0
  }

  func testCurrentStateDoesNotRetryUnchangedDeniedReplacement() async throws {
    let fixture = try ControlledSystemHelperLifecycleFixture(
      testCase: self,
      active: .unreachable,
      serviceStatus: .notRegistered,
      registerBehavior: .operationNotPermitted
    )
    fixture.replacementJournal.recordPendingReplacement()
    let harness = try ControlledXPCHarness(lifecycleFixture: fixture)
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()

    let initialState = await harness.reconcile(.startup)
    expect(initialState) == .approvalRequired
    let initialAttemptCount = fixture.service.registerAttemptCount
    expect(initialAttemptCount) > 0

    try await harness.client.refreshCurrentState()
    try await harness.client.refreshCurrentState()

    expect(harness.client.runtimeState.systemHelper) == .approvalRequired
    expect(fixture.service.status) == .notRegistered
    expect(fixture.replacementJournal.hasPendingReplacement) == true
    expect(fixture.service.registerAttemptCount) == initialAttemptCount
  }

  func testReconnectedAgentResumesApprovalWithoutPublishingHeartbeatIdentity() async throws {
    let fixture = try ControlledSystemHelperLifecycleFixture(
      testCase: self,
      active: .unreachable,
      serviceStatus: .requiresApproval
    )
    let harness = try ControlledXPCHarness(lifecycleFixture: fixture)
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()
    _ = await harness.reconcile(.startup)
    try await harness.client.refreshCurrentState()
    let backgroundService = TestControlAdapters.backgroundAgentService(mode: harness.appMode) {
      fail("Controlled approval test must not construct a production service")
      return GuidedBackgroundAgentService()
    }
    let state = InstallationState(
      backgroundAgentService: backgroundService,
      setupDefaults: harness.defaults
    )
    state.transitionSetup(to: .verifyingHelper)
    state.lastAutoRefreshAttemptedHash = "replacement-agent"
    let retiringGeneration = harness.client.connectionGeneration
    state.retiringAgentConnectionGeneration = retiringGeneration

    harness.invalidateMostRecentClientConnection()
    try await harness.waitForReplacementConnection()
    expect(harness.client.connectionGeneration) > retiringGeneration
    expect(harness.client.runtimeStateGeneration) == harness.client.connectionGeneration
    expect(harness.controllerIsPaused) == true
    let heartbeatIdentityExists =
      harness.defaults.object(forKey: SharedConfigKeys.agentExecutableHash) != nil
    expect(heartbeatIdentityExists) == false

    fixture.service.setStatus(.enabled)
    fixture.fanHardware.setIdentity(.identity(fixture.bundledIdentity))
    await state.refreshObservedSetup(agentClient: harness.client)

    expect(state.setupProgress) == .complete
    expect(harness.client.runtimeState.systemHelper)
      == .running(active: fixture.bundledIdentity)
    expect(fixture.service.registerAttemptCount) == 0
    expect(fixture.service.unregisterCount) == 0
  }
}
