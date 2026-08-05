//
//  TestControlXPCIntegrationTests+Commands.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

// MARK: - Command and connection coverage

@MainActor
extension TestControlXPCIntegrationTests {
  func testAutomaticHelperUpdateRecordsEvidence() async throws {
    let outdatedIdentity = TestSystemHelperIdentity(
      version: "0.3.0",
      build: "3",
      commit: "outdated-helper-commit",
      executableHash: "outdated-helper-full-hash",
      protocolVersion: 1
    )
    let bundledIdentity = TestHelperLifecycleState.bundledIdentity
    let outdatedLifecycle = TestHelperLifecycleState(
      active: .identity(outdatedIdentity),
      bundled: bundledIdentity,
      verificationBlocked: true
    )
    let harness = try ControlledXPCHarness(helperLifecycle: outdatedLifecycle)
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()
    let completion = TestControlBooleanObservation()
    let reconciliation = Task { @MainActor in
      defer { completion.record() }
      return await harness.reconcile(.startup)
    }
    defer { reconciliation.cancel() }

    try await harness.waitForSystemHelperState { state in
      if case .updating = state {
        return true
      }
      return false
    }
    try await harness.waitForAgentEvidence(
      .helperClassification(
        active: .identity(outdatedIdentity),
        bundled: bundledIdentity
      )
    )
    try await harness.waitForAgentEvidence(.helperFanReset(result: .succeed))

    expect(completion.value) == false
    expect(try harness.store.loadState().helperLifecycle.active)
      == .identity(outdatedIdentity)
    expect(try harness.agentEvidence()).toNot(
      contain(.helperIdentityVerified(bundledIdentity))
    )

    try harness.applyHelperLifecycle(
      TestHelperLifecycleState(
        active: .identity(bundledIdentity),
        bundled: bundledIdentity,
        verificationBlocked: false
      )
    )
    let result = await reconciliation.value

    expect(result) == .running(active: SystemHelperIdentity(bundledIdentity))
    try harness.assertSuccessfulHelperReplacement(beforeVerifiedIdentity: bundledIdentity)
  }

  func testControlledCommandsTraverseRealXPCAndWriteParticipantEvidence() async throws {
    let harness = try ControlledXPCHarness()
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()

    try await harness.client.setFanRPM(
      ControlledXPCTestValues.commandedFanIndex,
      rpm: ControlledXPCTestValues.commandedFanRPM
    )
    try await harness.client.setFanAuto(0)
    let ownership = try await harness.client.getOwnership()

    expect(ownership.map(\.clientName)) == ["FanCurveAgent"]
    let appPayloads = try harness.store.loadEvents(for: .app).map(\.payload)
    let agentPayloads = try harness.store.loadEvents(for: .agent).map(\.payload)
    expect(appPayloads).to(contain(.appToAgentCommand(command: .requestFanRPM)))
    expect(appPayloads).to(contain(.appToAgentCommand(command: .requestFanAuto)))
    expect(agentPayloads).to(
      contain(
        .fanWrite(
          fanIndex: ControlledXPCTestValues.commandedFanEventIndex,
          rpm: ControlledXPCTestValues.commandedFanRPM,
          priority: ControlledXPCTestValues.commandPriority
        )
      )
    )
    expect(agentPayloads).to(contain(.fanAutoReset(fanIndex: 0)))
    expect(harness.connectionFactoryCount)
      == ControlledXPCTestValues.initialConnectionCount
  }

  func testCancelledCommandBeforeDispatchDoesNotReachAgentHardware() async throws {
    let harness = try ControlledXPCHarness()
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()
    harness.suspendRequestDispatch()

    let commandTask = Task { @MainActor in
      try await harness.client.setFanRPM(
        ControlledXPCTestValues.commandedFanIndex,
        rpm: ControlledXPCTestValues.commandedFanRPM
      )
    }
    try await harness.waitForPendingRequestDispatch()
    commandTask.cancel()
    harness.resumeNextRequestDispatch()
    let error = await captureError {
      try await commandTask.value
    }

    expect(error is CancellationError) == true
    expect(harness.client.pendingRequestCount) == 0
    let agentPayloads = try harness.store.loadEvents(for: .agent).map(\.payload)
    expect(agentPayloads).toNot(
      contain(
        .fanWrite(
          fanIndex: ControlledXPCTestValues.commandedFanEventIndex,
          rpm: ControlledXPCTestValues.commandedFanRPM,
          priority: ControlledXPCTestValues.commandPriority
        )
      )
    )
  }

  func testDelayedProxyErrorFromReplacedConnectionPreservesCurrentCommand() async throws {
    let harness = try ControlledXPCHarness(recordsProxyErrorHandlers: true)
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()
    expect(harness.retainMostRecentProxyErrorHandler()) == true
    harness.restartClient()
    try await harness.waitForReplacementConnection()
    harness.suspendRequestDispatch()

    let commandTask = Task { @MainActor in
      try await harness.client.setFanRPM(
        ControlledXPCTestValues.commandedFanIndex,
        rpm: ControlledXPCTestValues.commandedFanRPM
      )
    }
    try await harness.waitForPendingRequestDispatch()
    harness.triggerRetainedProxyErrorHandler()
    await flushMainQueue()
    harness.resumeNextRequestDispatch()
    try await commandTask.value

    expect(harness.client.connectionState) == .connected
    let agentPayloads = try harness.store.loadEvents(for: .agent).map(\.payload)
    expect(agentPayloads).to(
      contain(
        .fanWrite(
          fanIndex: ControlledXPCTestValues.commandedFanEventIndex,
          rpm: ControlledXPCTestValues.commandedFanRPM,
          priority: ControlledXPCTestValues.commandPriority
        )
      )
    )
  }

  func testCommandFaultsAreOneShotAndRecordedBeforeTheirReplyEffect() async throws {
    for fault in [TestXPCFault.rejectedCommand, .malformedReply] {
      let harness = try ControlledXPCHarness(fault: fault)
      try await harness.startAndWaitUntilConnected()

      let firstError = await captureError {
        try await harness.client.setBoostEnabled(true)
      }
      expect(firstError) != nil
      try await harness.client.setBoostEnabled(true)

      expect(harness.faultEvidenceObservedBeforeEffect[fault]) == true
      let consumedFaults = try harness.store.loadEvents(for: .agent)
        .filter { $0.payload == .xpcFault(fault) }
      expect(consumedFaults).to(haveCount(1))
      harness.stop()
    }
  }

  func testCommandCompletesWhenAgentInvalidatesWithoutReply() async throws {
    let harness = try ControlledXPCHarness()
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()
    try harness.applyState(
      revision: ControlledXPCTestValues.controlledRevision,
      fault: .interruption
    )

    let error = await operationErrorWithinTimeout {
      try await harness.client.setBoostEnabled(true)
    }

    expect(error) != nil
    expect(harness.processTerminationCount) == 1
  }

  func testOwnershipCompletesWhenAgentInvalidatesWithoutReply() async throws {
    let harness = try ControlledXPCHarness()
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()
    try harness.applyState(
      revision: ControlledXPCTestValues.controlledRevision,
      fault: .interruption
    )

    let error = await operationErrorWithinTimeout {
      _ = try await harness.client.getOwnership()
    }

    expect(error) != nil
    expect(harness.processTerminationCount) == 1
  }

  func testAutomaticReconnectRechecksMissingAgentGate() async throws {
    let harness = try ControlledXPCHarness()
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()
    try harness.applyState(
      revision: ControlledXPCTestValues.controlledRevision,
      backgroundAgentStatus: .notRegistered
    )

    harness.invalidateMostRecentClientConnection()
    try await harness.waitForConnectionState(
      .failed("Controlled Background Agent is not enabled")
    )

    expect(harness.connectionFactoryCount)
      == ControlledXPCTestValues.initialConnectionCount
    let gatedEvents = try harness.store.loadEvents(for: .app)
      .filter { $0.payload == .xpcState(.connectionAttemptGated) }
    expect(gatedEvents).to(haveCount(1))
  }

  func testStaleInvalidationPreservesReplacementConnectionCallback() async throws {
    let harness = try ControlledXPCHarness()
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()
    let replacementClient = harness.makeAdditionalClient()
    defer { replacementClient.stop() }
    replacementClient.start()
    try await harness.waitUntilConnected(replacementClient)
    expect(harness.registeredEventCallbackCount)
      == ControlledXPCTestValues.registeredClientCount

    let acceptedBefore = try harness.acceptedRuntimeEventCount()
    harness.client.stop()
    try await harness.waitForRegisteredEventCallbackCount(1)
    harness.publishRuntimeState()
    try await harness.waitForAcceptedRuntimeEventCount(
      acceptedBefore + ControlledXPCTestValues.eventCountIncrement
    )

    expect(replacementClient.connectionState) == .connected
  }

  private func operationErrorWithinTimeout(
    operation: @escaping @MainActor () async throws -> Void
  ) async -> Error? {
    let completed = expectation(description: "XPC operation completed")
    var operationError: Error?
    let operationTask = Task { @MainActor in
      operationError = await captureError(operation)
      completed.fulfill()
    }
    await fulfillment(
      of: [completed],
      timeout: TimeInterval(ControlledXPCTestValues.connectionTimeoutSeconds)
    )
    operationTask.cancel()
    return operationError
  }

  private func flushMainQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume()
      }
    }
  }
}

// MARK: - Controlled System Helper lifecycle evidence

@MainActor
extension ControlledXPCHarness {
  func agentEvidence() throws -> [TestControlEventPayload] {
    try store.loadEvents(for: .agent).map(\.payload)
  }

  func assertSuccessfulHelperReplacement(
    beforeVerifiedIdentity identity: TestSystemHelperIdentity
  ) throws {
    let evidence = try agentEvidence()
    let unregisterIndex = try XCTUnwrap(
      evidence.firstIndex(
        of: .serviceMutation(
          service: .helper,
          operation: .unregister,
          result: .succeed
        )
      )
    )
    let registerIndex = try XCTUnwrap(
      evidence[evidence.index(after: unregisterIndex)...].firstIndex(
        of: .serviceMutation(
          service: .helper,
          operation: .register,
          result: .succeed
        )
      )
    )
    let verifiedIdentityIndex = try XCTUnwrap(
      evidence[evidence.index(after: registerIndex)...].firstIndex(
        of: .helperIdentityVerified(identity)
      )
    )
    expect(unregisterIndex) < registerIndex
    expect(registerIndex) < verifiedIdentityIndex
  }

  func waitForAgentEvidence(
    _ payload: TestControlEventPayload
  ) async throws {
    let revision = try store.loadState().revision.value
    let store = store
    let event: TestControlEvent = try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(
          with: Result {
            try store.waitForEvent(
              participant: .agent,
              kind: payload.kind,
              revision: revision,
              timeout: ControlledXPCTestValues.connectionTimeoutSeconds
            )
          }
        )
      }
    }
    guard event.payload == payload else {
      throw TestControlError.invalidArguments(
        "Unexpected System Helper lifecycle evidence"
      )
    }
  }

  func applyHelperLifecycle(_ lifecycle: TestHelperLifecycleState) throws {
    let currentState = try store.loadState()
    let revision = currentState.revision.value + 1
    try store.apply(
      TestControlState(
        sessionID: sessionID,
        revision: revision,
        services: currentState.services,
        hardware: currentState.hardware,
        xpcFault: currentState.xpcFault,
        helperLifecycle: lifecycle
      )
    )
    _ = try store.waitForAcknowledgment(
      participant: .agent,
      revision: revision,
      timeout: ControlledXPCTestValues.connectionTimeoutSeconds
    )
    _ = try store.waitForAcknowledgment(
      participant: .app,
      revision: revision,
      timeout: ControlledXPCTestValues.connectionTimeoutSeconds
    )
  }
}

// MARK: - ControlledXPCHarness request lifecycle

@MainActor
extension ControlledXPCHarness {
  var remoteProxyProvider: any AgentXPCRemoteProxyProviding {
    if recordsProxyErrorHandlers {
      return proxyErrorHandlerRecorder
    }
    return NSXPCRemoteProxyProvider()
  }

  func restartClient() {
    client.stop()
    client.start()
  }

  func suspendRequestDispatch() {
    requestDispatchController.suspend()
  }

  func resumeNextRequestDispatch() {
    requestDispatchController.resumeNext()
  }

  func retainMostRecentProxyErrorHandler() -> Bool {
    proxyErrorHandlerRecorder.retainMostRecentHandler()
  }

  func triggerRetainedProxyErrorHandler() {
    proxyErrorHandlerRecorder.triggerRetainedHandler()
  }
}
