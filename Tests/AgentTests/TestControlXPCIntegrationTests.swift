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

enum ControlledXPCTestValues {
  static let connectionTimeoutSeconds = 2
  static let pollingIntervalMilliseconds = 10
  static let reconnectDelay: TimeInterval = 0.01
  static let controlledRevision: UInt64 = 2
  static let commandedFanIndex: UInt = 1
  static let commandedFanEventIndex = 1
  static let commandedFanRPM: Float = 4_500
  static let commandPriority = 0
  static let initialConnectionCount = 1
  static let replacementConnectionCount = 2
  static let registeredClientCount = 2
  static let eventCountIncrement = 1
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
      expect(harness.client.pendingRequestCount) == 0
    }
  }
}

// MARK: - ControlledXPCHarness

@MainActor
final class ControlledXPCHarness {
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
  let recordsProxyErrorHandlers: Bool
  private let connectionCounter = XPCConnectionCounter()
  private let connectionRegistry = XPCConnectionRegistry()
  private let faultObservations = XPCFaultObservations()
  let requestDispatchController = XPCRequestDispatchController()
  let proxyErrorHandlerRecorder = XPCProxyErrorHandlerRecorder()
  private lazy var connectionFactory = XPCConnectionFactory(
    listener: listener,
    counter: connectionCounter,
    registry: connectionRegistry
  )
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

  var registeredEventCallbackCount: Int {
    service.currentEventCallbacks().count
  }

  init(
    backgroundAgentStatus: TestManagedServiceStatus = .enabled,
    fault: TestXPCFault = .noFault,
    recordsProxyErrorHandlers: Bool = false
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
    self.recordsProxyErrorHandlers = recordsProxyErrorHandlers
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
    return FanCurveAgentClient(
      serviceName: "anonymous-test-service",
      connectionFactory: { self.connectionFactory.makeConnection() },
      control: appControl,
      reconnectDelay: ControlledXPCTestValues.reconnectDelay,
      requestDispatcher: requestDispatchController,
      remoteProxyProvider: remoteProxyProvider
    )
  }
}

// MARK: - ControlledXPCHarness operations

@MainActor
extension ControlledXPCHarness {
  func makeAdditionalClient() -> FanCurveAgentClient {
    makeClient()
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
      timeout: 1
    )
    _ = try store.waitForAcknowledgment(
      participant: .app,
      revision: revision,
      timeout: 1
    )
  }

  func invalidateMostRecentClientConnection() {
    connectionRegistry.invalidateMostRecent()
  }

  func waitForPendingRequestDispatch() async throws {
    try await waitForCondition("pending XPC request dispatch") {
      self.requestDispatchController.pendingOperationCount == 1
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
    do {
      try store.withExclusiveLocks(
        fileNames: TestControlFile.evidenceLocksInOrder[...]
      ) {
        try FileManager.default.removeItem(at: store.directory)
      }
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
