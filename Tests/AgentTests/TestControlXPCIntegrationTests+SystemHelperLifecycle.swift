//
//  TestControlXPCIntegrationTests+SystemHelperLifecycle.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Combine
import Foundation
import Nimble
import XCTest

private enum HelperLifecycleTestValues {
  static let blockedIdentityDelaySeconds: Int64 = 5
  static let verificationIdentityDelayMilliseconds: Int64 = 80
  static let concurrentMutationDelayMilliseconds: Int64 = 60
  static let blockedIdentityDelay: Duration = .seconds(blockedIdentityDelaySeconds)
  static let verificationIdentityDelay: Duration = .milliseconds(
    verificationIdentityDelayMilliseconds
  )
  static let concurrentMutationDelay: Duration = .milliseconds(
    concurrentMutationDelayMilliseconds
  )
  static let expectationTimeout: TimeInterval = 1
  static let noRegistrationGeneration = 0
  static let originalRegistrationGeneration = 1
  static let replacementRegistrationGeneration = 2
  static let noUnregistrations = 0
  static let oneUnregistration = 1
  static let protocolVersion: UInt = 1
}

// MARK: - System Helper lifecycle XPC coverage

@MainActor
extension TestControlXPCIntegrationTests {
  func testListenerAcceptsClientWhileStartupReconciliationIsChecking() async throws {
    let identityRequestStarted = expectation(description: "identity request started")
    let fixture = try ControlledSystemHelperLifecycleFixture(
      testCase: self,
      active: .bundled,
      identityDelay: HelperLifecycleTestValues.blockedIdentityDelay,
      identityRequestStarted: identityRequestStarted
    )
    let harness = try ControlledXPCHarness(lifecycleFixture: fixture)
    defer { harness.stop() }
    harness.startListener()
    let startup = Task { @MainActor in
      await harness.reconcile(.startup)
    }
    defer { startup.cancel() }
    await fulfillment(
      of: [identityRequestStarted],
      timeout: HelperLifecycleTestValues.expectationTimeout
    )

    harness.startClient()
    try await harness.waitUntilConnected()

    expect(harness.client.runtimeState.systemHelper) == .checking
    expect(harness.controllerIsPaused) == true
    startup.cancel()
    _ = await startup.value
  }

  func testStartupPublishesCheckingUpdatingRunningBeforeControllerResumes() async throws {
    let fixture = try ControlledSystemHelperLifecycleFixture(
      testCase: self,
      active: .outdated
    )
    let harness = try ControlledXPCHarness(lifecycleFixture: fixture)
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()
    var observations: [(SystemHelperStateKind, Bool)] = []
    let observation = harness.client.$runtimeState.sink { state in
      observations.append((systemHelperStateKind(state.systemHelper), harness.controllerIsPaused))
    }

    let result = await harness.reconcile(.startup)
    try await harness.waitForSystemHelperState { state in
      systemHelperStateKind(state) == .running
    }

    expect(result) == .running(active: fixture.bundledIdentity)
    expect(
      containsSubsequence(
        observations.map(\.0),
        expected: [.checking, .updating, .running]
      )
    ) == true
    expect(observations.first { $0.0 == .checking }?.1) == true
    expect(observations.first { $0.0 == .updating }?.1) == true
    withExtendedLifetime(observation) {
      expect(observations.last { $0.0 == .running }?.1) == false
    }
  }

  func testManualRepairReplyWaitsForVerifiedActiveHash() async throws {
    let verificationGate = IdentityVerificationGate()
    let fixture = try ControlledSystemHelperLifecycleFixture(
      testCase: self,
      active: .bundled,
      identityDelay:
        HelperLifecycleTestValues.verificationIdentityDelay,
      verificationGate: verificationGate
    )
    let harness = try ControlledXPCHarness(lifecycleFixture: fixture)
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()
    let completion = TestControlBooleanObservation()
    let repair = Task { @MainActor in
      defer { completion.record() }
      try await harness.client.installOrRepairHelper()
    }
    defer { repair.cancel() }
    await verificationGate.waitForArrival()

    expect(completion.value) == false
    await verificationGate.resume()
    try await repair.value
    try await harness.waitForSystemHelperState { state in
      systemHelperStateKind(state) == .running
    }

    expect(harness.client.runtimeState.systemHelper)
      == .running(active: fixture.bundledIdentity)
    expect(fixture.service.registrationGeneration)
      == HelperLifecycleTestValues.replacementRegistrationGeneration
  }

  func testRegistrationFailureReturnsAndPublishesDurableFailure() async throws {
    let fixture = try ControlledSystemHelperLifecycleFixture(
      testCase: self,
      active: .outdated,
      registerBehavior: .fail
    )
    let harness = try ControlledXPCHarness(lifecycleFixture: fixture)
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()

    let error = await captureError {
      try await harness.client.installOrRepairHelper()
    }
    try await harness.waitForSystemHelperState { state in
      systemHelperStateKind(state) == .repairFailed
    }

    expect(error?.localizedDescription) == "register"
    guard
      case .repairFailed(_, _, let failure) =
        harness.client.runtimeState.systemHelper
    else {
      XCTFail("Expected durable System Helper repair failure")
      return
    }
    expect(failure.operation) == .forcedRepair
    expect(failure.stage) == .register
    expect(failure.reason) == "register"
    expect(fixture.service.unregisterCount)
      == HelperLifecycleTestValues.oneUnregistration
    expect(harness.controllerIsPaused) == true
  }

  func testHealthyReconnectDoesNotMutateRegistrationAgain() async throws {
    let fixture = try ControlledSystemHelperLifecycleFixture(
      testCase: self,
      active: .bundled
    )
    let harness = try ControlledXPCHarness(lifecycleFixture: fixture)
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()

    _ = await harness.reconcile(.startup)
    let reconnectState = await harness.reconcile(.reconnect)

    expect(reconnectState) == .running(active: fixture.bundledIdentity)
    expect(fixture.service.registrationGeneration)
      == HelperLifecycleTestValues.originalRegistrationGeneration
    expect(fixture.service.unregisterCount)
      == HelperLifecycleTestValues.noUnregistrations
    expect(harness.controllerIsPaused) == false
  }

  func testConcurrentManualRepairCommandsShareReconciliation() async throws {
    let fixture = try ControlledSystemHelperLifecycleFixture(
      testCase: self,
      active: .bundled,
      mutationDelay: HelperLifecycleTestValues.concurrentMutationDelay
    )
    let harness = try ControlledXPCHarness(lifecycleFixture: fixture)
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()

    async let first: Void = harness.client.installOrRepairHelper()
    async let second: Void = harness.client.installOrRepairHelper()
    try await first
    try await second

    expect(fixture.service.registrationGeneration)
      == HelperLifecycleTestValues.replacementRegistrationGeneration
    expect(fixture.service.unregisterCount)
      == HelperLifecycleTestValues.oneUnregistration
  }

}

// MARK: - ControlledSystemHelperLifecycleFixture

final class ControlledSystemHelperLifecycleFixture: @unchecked Sendable {
  let artifactValidator: any SystemHelperArtifactValidating
  let bundledIdentity: SystemHelperIdentity
  let executableURL: URL
  let fanHardware: StatefulFanHardware
  let fanResetDeadline = ControlledXPCTestValues.systemHelperFanResetDeadline
  let service: StatefulHelperService
  let verificationPollInterval =
    ControlledXPCTestValues.systemHelperVerificationPollInterval
  let verificationTimeout =
    ControlledXPCTestValues.systemHelperVerificationTimeout

  init(
    testCase: XCTestCase,
    active: ReconcilerHarness.ActiveFixture,
    serviceStatus: ManagedServiceStatus = .enabled,
    registerBehavior: ReconcilerHarness.OperationBehavior = .succeed,
    identityDelay: Duration = .zero,
    identityRequestStarted: XCTestExpectation? = nil,
    verificationStarted: XCTestExpectation? = nil,
    verificationGate: IdentityVerificationGate? = nil,
    mutationDelay: Duration = .zero
  ) throws {
    let artifactFixture = try SystemHelperArtifactFixture.make(testCase: testCase)
    executableURL = artifactFixture.executableURL
    artifactValidator = artifactFixture.validator
    bundledIdentity = artifactFixture.identity
    let outdatedIdentity = SystemHelperIdentity(
      version: "1.0.0",
      build: "10",
      commit: "outdated-commit",
      executableHash: "outdated-hash",
      protocolVersion: HelperLifecycleTestValues.protocolVersion
    )
    fanHardware = StatefulFanHardware(
      identity: Self.identityBehavior(
        active,
        bundledIdentity: bundledIdentity,
        outdatedIdentity: outdatedIdentity
      ),
      identityDelay: identityDelay,
      identityRequestStarted: identityRequestStarted,
      additionalVerificationStarted: nil,
      legacyProbeStarted: nil,
      legacyProbeCancelled: nil,
      verificationStarted: verificationStarted,
      verificationGate: verificationGate,
      resetBehavior: .succeed
    )
    service = StatefulHelperService(
      status: serviceStatus,
      registrationGeneration: serviceStatus == .notRegistered
        ? HelperLifecycleTestValues.noRegistrationGeneration
        : HelperLifecycleTestValues.originalRegistrationGeneration,
      unregisterFails: false,
      registerBehavior: registerBehavior,
      unregisterStarted: nil,
      unregisterCompleted: nil,
      mutationDelay: mutationDelay
    )
    service.setOnRegistered { [fanHardware, bundledIdentity] in
      fanHardware.setIdentity(.identity(bundledIdentity))
    }
  }

  private static func identityBehavior(
    _ active: ReconcilerHarness.ActiveFixture,
    bundledIdentity: SystemHelperIdentity,
    outdatedIdentity: SystemHelperIdentity
  ) -> StatefulFanHardware.IdentityBehavior {
    switch active {
    case .bundled:
      return .identity(bundledIdentity)
    case .legacy:
      return .legacy
    case .outdated:
      return .identity(outdatedIdentity)
    case .unreachable:
      return .unreachable
    }
  }
}

// MARK: - SystemHelperStateKind

private enum SystemHelperStateKind: Equatable {
  case approvalRequired
  case checking
  case outdated
  case registrationNeedsRepair
  case repairFailed
  case running
  case unavailable
  case updating
}

// MARK: - SystemHelperRuntimeState

private func systemHelperStateKind(
  _ state: SystemHelperRuntimeState
) -> SystemHelperStateKind {
  switch state {
  case .approvalRequired:
    return .approvalRequired
  case .checking:
    return .checking
  case .outdated:
    return .outdated
  case .registrationNeedsRepair:
    return .registrationNeedsRepair
  case .repairFailed:
    return .repairFailed
  case .running:
    return .running
  case .unavailable:
    return .unavailable
  case .updating:
    return .updating
  }
}

// MARK: - Array

private func containsSubsequence<Element: Equatable>(
  _ elements: [Element],
  expected: [Element]
) -> Bool {
  var expectedIndex = expected.startIndex
  for element in elements {
    guard expectedIndex < expected.endIndex else { return true }
    if element == expected[expectedIndex] {
      expected.formIndex(after: &expectedIndex)
    }
  }
  return expectedIndex == expected.endIndex
}
