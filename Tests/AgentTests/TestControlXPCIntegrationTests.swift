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

enum ControlledXPCTestValues {
  static let connectionTimeoutSeconds: TimeInterval = 2
  static let pollingIntervalMilliseconds = 10
  static let reconnectDelay: TimeInterval = 0.01
  static let controlledRevision: UInt64 = 2
  static let commandedFanIndex: UInt = 1
  static let firstFanIndex = 0
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
  static let systemHelperFanResetDeadline: TimeInterval = 0.05
  static let helperVerificationTimeoutMilliseconds: Int64 = 300
  static let systemHelperVerificationPollInterval: Duration = .milliseconds(
    pollingIntervalMilliseconds
  )
  static let systemHelperVerificationTimeout: Duration = .milliseconds(
    helperVerificationTimeoutMilliseconds
  )
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
        revision: ControlledXPCTestValues.controlledRevision,
        backgroundAgentStatus: .enabled,
        fault: .noFault
      )
    )
    _ = try harness.store.waitForAcknowledgment(
      participant: .app,
      revision: ControlledXPCTestValues.controlledRevision,
      timeout: ControlledXPCTestValues.connectionTimeoutSeconds
    )
    harness.start()
    try await harness.waitUntilConnected()

    expect(harness.connectionFactoryCount)
      == ControlledXPCTestValues.initialConnectionCount
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

// MARK: - ControlledXPCLifecycleDependencies

private struct ControlledXPCLifecycleDependencies {
  let executableURL: URL
  let hardware: any FanHardware
  let service: any HelperServiceManaging
}

// MARK: - ControlledXPCHarness

@MainActor
final class ControlledXPCHarness {
  let store: TestControlSessionStore
  private(set) lazy var client = makeClient()

  let sessionID = UUID()
  let defaultsSuiteName = "io.goodkind.fancurve.xpc-tests.\(UUID().uuidString)"
  let defaults: UserDefaults
  let listener: NSXPCListener
  lazy var service = makeService()
  let appMode: TestControlRuntimeMode
  let agentMode: TestControlRuntimeMode
  let controller: AgentController
  private let helperService: any HelperServiceManaging
  private let reconciler: SystemHelperLifecycleReconciler
  private let evidenceReader: XPCFaultEvidenceReader
  let recordsProxyErrorHandlers: Bool
  private let connectionCounter = XPCConnectionCounter()
  let connectionRegistry = XPCConnectionRegistry()
  private let faultObservations = XPCFaultObservations()
  let requestDispatchController = XPCRequestDispatchController()
  let proxyErrorHandlerRecorder = XPCProxyErrorHandlerRecorder()
  private lazy var connectionFactory = XPCConnectionFactory(
    listener: listener,
    counter: connectionCounter,
    registry: connectionRegistry
  )
  var serviceStarted = false

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
    recordsProxyErrorHandlers: Bool = false,
    lifecycleFixture: ControlledSystemHelperLifecycleFixture? = nil
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
    let lifecycleDependencies = try Self.makeLifecycleDependencies(
      directory: directory,
      agentMode: agentMode,
      lifecycleFixture: lifecycleFixture
    )
    self.helperService = lifecycleDependencies.service
    self.controller = AgentController(
      fanHardware: lifecycleDependencies.hardware,
      sharedConfig: sharedConfig
    )
    self.reconciler = SystemHelperLifecycleReconciler(
      fanHardware: lifecycleDependencies.hardware,
      service: helperService,
      lifecycleGate: controller,
      bundledExecutableURL: lifecycleDependencies.executableURL,
      artifactValidator: lifecycleFixture?.artifactValidator
        ?? HashingArtifactValidator(),
      fanResetDeadline: lifecycleFixture?.fanResetDeadline
        ?? ControlledXPCTestValues.systemHelperFanResetDeadline,
      verificationTimeout: lifecycleFixture?.verificationTimeout
        ?? ControlledXPCTestValues.systemHelperVerificationTimeout,
      verificationPollInterval: lifecycleFixture?.verificationPollInterval
        ?? ControlledXPCTestValues.systemHelperVerificationPollInterval
    ) { [controller] state in
      controller.updateSystemHelperRuntimeState(state)
    }
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
      reconciler: reconciler,
      faultController: agentFaultControl
    ) {
      agentFaultObserver.recordInterruptionTermination()
    }
  }

  func makeClient() -> FanCurveAgentClient {
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

  private static func bundledHelperExecutableURL(
    in directory: URL
  ) throws -> URL {
    let executableURL = directory.appendingPathComponent("SystemHelper")
    try Data("controlled-system-helper".utf8).write(to: executableURL)
    return executableURL
  }

  private static func makeLifecycleDependencies(
    directory: URL,
    agentMode: TestControlRuntimeMode,
    lifecycleFixture: ControlledSystemHelperLifecycleFixture?
  ) throws -> ControlledXPCLifecycleDependencies {
    if let lifecycleFixture {
      return ControlledXPCLifecycleDependencies(
        executableURL: lifecycleFixture.executableURL,
        hardware: lifecycleFixture.fanHardware,
        service: lifecycleFixture.service
      )
    }
    let controlledHardware = AgentTestControlAdapters.fanHardware(mode: agentMode) {
      XCTFail("Controlled XPC harness constructed production hardware")
      return XPCFallbackHardware()
    }
    let controlledService = AgentTestControlAdapters.helperService(mode: agentMode) {
      XCTFail("Controlled XPC harness constructed production helper service")
      return XPCFallbackService()
    }
    return try ControlledXPCLifecycleDependencies(
      executableURL: bundledHelperExecutableURL(
        in: directory
      ),
      hardware: controlledHardware,
      service: controlledService
    )
  }
}
