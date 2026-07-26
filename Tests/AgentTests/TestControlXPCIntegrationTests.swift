//
//  TestControlXPCIntegrationTests.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation
import Nimble
import XCTest

private let controlledXPCIntegrationTestLog = AppLog.make(
  category: "ControlledXPCIntegrationTests"
)

private enum ControlledXPCTestValues {
  static let connectionTimeoutSeconds = 2
  static let pollingIntervalMilliseconds = 10
  static let reconnectDelay: TimeInterval = 0.01
  static let leftActualRPM: Float = 2_100
  static let leftTargetRPM: Float = 2_200
  static let leftMinimumRPM: Float = 1_200
  static let leftMaximumRPM: Float = 5_800
  static let rightActualRPM: Float = 3_300
  static let rightTargetRPM: Float = 3_400
  static let rightMinimumRPM: Float = 1_300
  static let rightMaximumRPM: Float = 5_900
  static let cpuTemperatureC = 72.0
  static let cpuLoadPercent = 42.0
  static let gpuLoadPercent = 18.0
  static let ownershipPriority = 50
}

// MARK: - TestControlXPCIntegrationTests

@MainActor
final class TestControlXPCIntegrationTests: XCTestCase {
  func testControlledCommandsTraverseRealXPCAndWriteParticipantEvidence() async throws {
    let harness = try ControlledXPCHarness()
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()

    try await harness.client.setFanRPM(1, rpm: 4_500)
    try await harness.client.setFanAuto(0)
    let ownership = try await harness.client.getOwnership()

    expect(ownership.map(\.clientName)) == ["FanCurveAgent"]
    let appPayloads = try harness.store.loadEvents(for: .app).map(\.payload)
    let agentPayloads = try harness.store.loadEvents(for: .agent).map(\.payload)
    expect(appPayloads).to(contain(.appToAgentCommand(command: .requestFanRPM)))
    expect(appPayloads).to(contain(.appToAgentCommand(command: .requestFanAuto)))
    expect(agentPayloads).to(contain(.fanWrite(fanIndex: 1, rpm: 4_500, priority: 0)))
    expect(agentPayloads).to(contain(.fanAutoReset(fanIndex: 0)))
    expect(harness.connectionFactoryCount) == 1
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

  func testMalformedInitialStateFaultIsOneShotAcrossReconnect() async throws {
    try await verifyStartupFault(.malformedInitialState)
  }

  func testMalformedEventFaultIsOneShotAndRejected() async throws {
    try await verifyStartupFault(.malformedEvent)
  }

  func testDuplicateEventFaultIsOneShotAndDeliversTwice() async throws {
    try await verifyStartupFault(.duplicateEvent)
  }

  func testInvalidationFaultIsOneShotAcrossReconnect() async throws {
    try await verifyStartupFault(.invalidation)
  }

  func testInterruptionFaultIsOneShotAcrossAgentTermination() async throws {
    try await verifyStartupFault(.interruption)
  }

  func testReconnectFaultIsOneShotAcrossClientReconnect() async throws {
    try await verifyStartupFault(.reconnect)
  }

  func testMissingAgentGatePreventsConnectionConstructionUntilEnabled() async throws {
    let harness = try ControlledXPCHarness(backgroundAgentStatus: .notRegistered)
    defer { harness.stop() }

    harness.start()
    expect(harness.connectionFactoryCount) == 0
    expect(harness.client.connectionState)
      == .failed("Controlled Background Agent is not enabled")
    expect(try harness.store.loadEvents(for: .app).map(\.payload)).to(
      contain(.xpcState(.connectionAttemptGated))
    )

    try harness.store.apply(
      harness.makeState(
        revision: 2,
        backgroundAgentStatus: .enabled,
        fault: .noFault
      )
    )
    _ = try harness.store.waitForAcknowledgment(
      participant: .app,
      revision: 2,
      timeout: 1
    )
    harness.start()
    try await harness.waitUntilConnected()

    expect(harness.connectionFactoryCount) == 1
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

  private func verifyStartupFault(_ fault: TestXPCFault) async throws {
    let harness = try ControlledXPCHarness(fault: fault)
    defer { harness.stop() }
    try await harness.startAndWaitUntilConnected()

    let participant: TestControlParticipant = fault == .reconnect ? .app : .agent
    let consumedFaults = try harness.store.loadEvents(for: participant)
      .filter { $0.payload == .xpcFault(fault) }
    expect(consumedFaults).to(haveCount(1))
    expect(harness.faultEvidenceObservedBeforeEffect[fault]) == true

    if fault == .malformedEvent {
      let rejectedEvents = try harness.store.loadEvents(for: .app)
        .filter { $0.payload == .xpcState(.runtimeEventRejected) }
      expect(rejectedEvents).to(haveCount(1))
    }
    if fault == .duplicateEvent {
      let acceptedEvents = try harness.store.loadEvents(for: .app)
        .filter { $0.payload == .xpcState(.runtimeEventAccepted) }
      expect(acceptedEvents).to(haveCount(2))
    }
    if [.malformedInitialState, .invalidation, .interruption, .reconnect].contains(fault) {
      expect(harness.connectionFactoryCount) >= 2
    }
    if fault == .interruption {
      expect(harness.processTerminationCount) == 1
    }
  }
}

// MARK: - ControlledXPCHarness

@MainActor
private final class ControlledXPCHarness {
  let store: TestControlSessionStore
  private(set) lazy var client = makeClient()

  private let sessionID = UUID()
  private let defaultsSuiteName = "io.goodkind.fancurve.xpc-tests.\(UUID().uuidString)"
  private let defaults: UserDefaults
  private let listener: NSXPCListener
  private lazy var service = makeService()
  private let appMode: TestControlRuntimeMode
  private let agentMode: TestControlRuntimeMode
  private let controller: AgentController
  private let helperService: any HelperServiceManaging
  private let evidenceReader: XPCFaultEvidenceReader
  private let connectionCounter = XPCConnectionCounter()
  private let faultObservations = XPCFaultObservations()
  private var serviceStarted = false

  var connectionFactoryCount: Int {
    connectionCounter.value
  }

  var processTerminationCount: Int {
    faultObservations.processTerminationCount
  }

  var faultEvidenceObservedBeforeEffect: [TestXPCFault: Bool] {
    faultObservations.evidenceByFault
  }

  init(
    backgroundAgentStatus: TestManagedServiceStatus = .enabled,
    fault: TestXPCFault = .noFault
  ) throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "FanCurveControlledXPC-\(UUID().uuidString)",
        isDirectory: true
      )
    self.store = try TestControlSessionStore.initialize(
      at: directory,
      initialState: Self.makeState(
        sessionID: sessionID,
        revision: 1,
        backgroundAgentStatus: backgroundAgentStatus,
        fault: fault
      )
    )
    self.evidenceReader = XPCFaultEvidenceReader(store: store)
    let activation = TestControlActivation.controlled(
      sessionID: sessionID,
      directory: directory
    )
    self.appMode = try TestControlRuntimeMode.resolve(
      participant: .app,
      activation: activation
    )
    self.agentMode = try TestControlRuntimeMode.resolve(
      participant: .agent,
      activation: activation
    )
    self.defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
    defaults.removePersistentDomain(forName: defaultsSuiteName)
    let sharedConfig = SharedConfig(defaults: defaults)
    let hardware = AgentTestControlAdapters.fanHardware(mode: agentMode) {
      XCTFail("Controlled XPC harness constructed production hardware")
      return XPCFallbackHardware()
    }
    self.helperService = AgentTestControlAdapters.helperService(mode: agentMode) {
      XCTFail("Controlled XPC harness constructed production helper service")
      return XPCFallbackService()
    }
    self.controller = AgentController(
      fanHardware: hardware,
      sharedConfig: sharedConfig
    )
    self.listener = NSXPCListener.anonymous()
  }

  private func makeService() -> FanCurveAgentXPCService {
    let agentFaultObserver = XPCFaultObserver(
      reader: evidenceReader,
      observations: faultObservations,
      participant: .agent
    )
    let agentFaultControl = TestControlAgentXPCFaultController(
      mode: agentMode,
      faultObserver: agentFaultObserver.observe
    )
    return FanCurveAgentXPCService(
      controller: controller,
      listener: listener,
      helperService: helperService,
      faultController: agentFaultControl
    ) {
      agentFaultObserver.recordInterruptionTermination()
    }
  }

  private func makeClient() -> FanCurveAgentClient {
    let appFaultObserver = XPCFaultObserver(
      reader: evidenceReader,
      observations: faultObservations,
      participant: .app
    )
    let appControl = TestControlAgentClientController(
      mode: appMode,
      faultObserver: appFaultObserver.observe
    )
    let connectionFactory = XPCConnectionFactory(
      listener: listener,
      counter: connectionCounter
    )
    return FanCurveAgentClient(
      serviceName: "anonymous-test-service",
      connectionFactory: { connectionFactory.makeConnection() },
      control: appControl,
      reconnectDelay: ControlledXPCTestValues.reconnectDelay
    )
  }

  func start() {
    if !serviceStarted {
      service.start()
      serviceStarted = true
    }
    client.start()
  }

  func startAndWaitUntilConnected() async throws {
    start()
    try await waitUntilConnected()
  }

  func waitUntilConnected() async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(
      by: .seconds(ControlledXPCTestValues.connectionTimeoutSeconds)
    )
    while clock.now < deadline {
      if client.connectionState == .connected {
        return
      }
      try await clock.sleep(
        for: .milliseconds(ControlledXPCTestValues.pollingIntervalMilliseconds)
      )
    }
    throw TestControlError.timeout("real XPC client connection")
  }

  func stop() {
    client.stop()
    listener.invalidate()
    if case .controlled(let runtime) = appMode {
      runtime.stopMonitoring()
    }
    if case .controlled(let runtime) = agentMode {
      runtime.stopMonitoring()
    }
    defaults.removePersistentDomain(forName: defaultsSuiteName)
    do {
      try FileManager.default.removeItem(at: store.directory)
    } catch {
      controlledXPCIntegrationTestLog.error(
        "test_control.xpc.cleanup_failed path=\(store.directory.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=report-test-failure"
      )
      XCTFail("Controlled XPC cleanup failed: \(error.localizedDescription)")
    }
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

  private static func makeState(
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
            fanIndex: 0,
            name: "Left Fan",
            actualRPM: ControlledXPCTestValues.leftActualRPM,
            targetRPM: ControlledXPCTestValues.leftTargetRPM,
            minimumRPM: ControlledXPCTestValues.leftMinimumRPM,
            maximumRPM: ControlledXPCTestValues.leftMaximumRPM,
            isAutomatic: true
          ),
          TestFanReading(
            fanIndex: 1,
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
            fanIndex: 1,
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
