//
//  ControlledXPCHarness+Operations.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - ControlledXPCHarness operations

@MainActor
extension ControlledXPCHarness {
  func makeAdditionalClient() -> FanCurveAgentClient {
    makeClient()
  }

  func start() {
    startListener()
    startClient()
  }

  func startListener() {
    if !serviceStarted {
      service.start()
      serviceStarted = true
    }
  }

  func startClient() {
    client.start()
  }

  func reconcile(_ trigger: SystemHelperReconcileTrigger) async -> SystemHelperRuntimeState {
    await service.reconcileSystemHelper(trigger: trigger)
  }

  var controllerIsPaused: Bool {
    controller.timer == nil
  }

  func startAndWaitUntilConnected() async throws {
    start()
    try await waitUntilConnected()
  }

  func waitUntilConnected() async throws {
    try await waitUntilConnected(client)
  }

  func waitUntilConnected(_ candidateClient: FanCurveAgentClient) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(
      by: .seconds(ControlledXPCTestValues.connectionTimeoutSeconds)
    )
    while clock.now < deadline {
      if candidateClient.connectionState == .connected {
        return
      }
      try await clock.sleep(
        for: .milliseconds(ControlledXPCTestValues.pollingIntervalMilliseconds)
      )
    }
    throw TestControlError.timeout("real XPC client connection")
  }

  func waitForConnectionState(
    _ expectedState: FanCurveAgentConnectionState
  ) async throws {
    try await waitForCondition("XPC connection state") {
      self.client.connectionState == expectedState
    }
  }

  func waitForRegisteredEventCallbackCount(_ expectedCount: Int) async throws {
    try await waitForCondition("registered XPC event callback count") {
      self.registeredEventCallbackCount == expectedCount
    }
  }

  func waitForAcceptedRuntimeEventCount(_ expectedCount: Int) async throws {
    try await waitForCondition("accepted runtime event count") {
      try self.acceptedRuntimeEventCount() >= expectedCount
    }
  }

  func waitForSystemHelperState(
    _ predicate: @escaping (SystemHelperRuntimeState) -> Bool
  ) async throws {
    try await waitForCondition("System Helper runtime state") {
      predicate(self.client.runtimeState.systemHelper)
    }
  }

  func acceptedRuntimeEventCount() throws -> Int {
    try store.loadEvents(for: .app)
      .filter { $0.payload == .xpcState(.runtimeEventAccepted) }
      .count
  }

  func applyState(
    revision: UInt64,
    backgroundAgentStatus: TestManagedServiceStatus = .enabled,
    fault: TestXPCFault = .noFault
  ) throws {
    try store.apply(
      makeState(
        revision: revision,
        backgroundAgentStatus: backgroundAgentStatus,
        fault: fault
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

  func invalidateMostRecentClientConnection() {
    connectionRegistry.invalidateMostRecent()
  }

  func waitForPendingRequestDispatch() async throws {
    try await waitForCondition("pending XPC request dispatch") {
      self.requestDispatchController.pendingOperationCount
        == ControlledXPCTestValues.initialConnectionCount
    }
  }

  func waitForReplacementConnection() async throws {
    try await waitForCondition("replacement XPC connection") {
      self.connectionFactoryCount
        >= ControlledXPCTestValues.replacementConnectionCount
        && self.client.connectionState == .connected
    }
  }

  func publishRuntimeState() {
    service.publishRuntimeState(controller.currentRuntimeStateForXPC())
  }

  func stop() {
    controller.pause()
    client.stop()
    listener.invalidate()
    service.invalidateConnections()
    if case .controlled(let runtime) = appMode {
      runtime.stopMonitoring()
    }
    if case .controlled(let runtime) = agentMode {
      runtime.stopMonitoring()
    }
    defaults.removePersistentDomain(forName: defaultsSuiteName)
    removeSessionDirectory()
    withExtendedLifetime((appMode, agentMode, service)) {
      _ = service
    }
  }

  func makeState(
    revision: UInt64,
    backgroundAgentStatus: TestManagedServiceStatus,
    fault: TestXPCFault
  ) -> TestControlState {
    Self.makeState(
      sessionID: sessionID,
      revision: revision,
      backgroundAgentStatus: backgroundAgentStatus,
      fault: fault
    )
  }

  private func waitForCondition(
    _ description: String,
    condition: () throws -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(
      by: .seconds(ControlledXPCTestValues.connectionTimeoutSeconds)
    )
    while clock.now < deadline {
      if try condition() {
        return
      }
      try await clock.sleep(
        for: .milliseconds(ControlledXPCTestValues.pollingIntervalMilliseconds)
      )
    }
    throw TestControlError.timeout(description)
  }

  static func makeState(
    sessionID: UUID,
    revision: UInt64,
    backgroundAgentStatus: TestManagedServiceStatus,
    fault: TestXPCFault
  ) -> TestControlState {
    TestControlState(
      sessionID: sessionID,
      revision: revision,
      services: TestServiceState(
        backgroundAgentStatus: backgroundAgentStatus,
        helperStatus: .enabled,
        nextOperation: .succeed
      ),
      hardware: TestHardwareState(
        sensorTemperatures: [
          TestSensorTemperature(
            name: "TC0P",
            temperatureC: ControlledXPCTestValues.cpuTemperatureC
          )
        ],
        fanReadings: [
          TestFanReading(
            fanIndex: ControlledXPCTestValues.firstFanIndex,
            name: "Left Fan",
            actualRPM: ControlledXPCTestValues.leftActualRPM,
            targetRPM: ControlledXPCTestValues.leftTargetRPM,
            minimumRPM: ControlledXPCTestValues.leftMinimumRPM,
            maximumRPM: ControlledXPCTestValues.leftMaximumRPM,
            isAutomatic: true
          ),
          TestFanReading(
            fanIndex: ControlledXPCTestValues.commandedFanEventIndex,
            name: "Right Fan",
            actualRPM: ControlledXPCTestValues.rightActualRPM,
            targetRPM: ControlledXPCTestValues.rightTargetRPM,
            minimumRPM: ControlledXPCTestValues.rightMinimumRPM,
            maximumRPM: ControlledXPCTestValues.rightMaximumRPM,
            isAutomatic: false
          ),
        ],
        ownership: [
          TestFanOwnership(
            fanIndex: ControlledXPCTestValues.commandedFanEventIndex,
            processName: "FanCurveAgent",
            priority: ControlledXPCTestValues.ownershipPriority
          )
        ],
        cpuLoadPercent: ControlledXPCTestValues.cpuLoadPercent,
        gpuLoadPercent: ControlledXPCTestValues.gpuLoadPercent,
        runtimeFlags: TestRuntimeFlags(
          helperReachable: true,
          telemetryStale: false
        ),
        nextOperation: .succeed
      ),
      xpcFault: fault
    )
  }
}
