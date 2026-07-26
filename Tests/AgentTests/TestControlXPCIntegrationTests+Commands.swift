//
//  TestControlXPCIntegrationTests+Commands.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

// MARK: - Command and connection coverage

@MainActor
extension TestControlXPCIntegrationTests {
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

  private func captureError(
    operation: () async throws -> Void
  ) async -> Error? {
    do {
      try await operation()
      return nil
    } catch {
      return error
    }
  }

  private func operationErrorWithinTimeout(
    operation: @escaping @MainActor () async throws -> Void
  ) async -> Error? {
    let completed = expectation(description: "XPC operation completed")
    var operationError: Error?
    let operationTask = Task { @MainActor in
      operationError = await captureError(operation: operation)
      completed.fulfill()
    }
    await fulfillment(
      of: [completed],
      timeout: TimeInterval(ControlledXPCTestValues.connectionTimeoutSeconds)
    )
    operationTask.cancel()
    return operationError
  }
}
