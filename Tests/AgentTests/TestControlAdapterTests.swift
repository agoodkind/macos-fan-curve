//
//  TestControlAdapterTests.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

final class TestControlAdapterTests: XCTestCase {
  private var temporaryDirectories: [URL] = []

  override func setUpWithError() throws {
    try super.setUpWithError()
    temporaryDirectories = []
  }

  override func tearDownWithError() throws {
    for directory in temporaryDirectories
    where FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
    temporaryDirectories.removeAll()
    try super.tearDownWithError()
  }

  func testControlledServiceMapsStatusAndReturnsConfiguredMutationFailure() throws {
    let sessionID = UUID()
    let store = try makeStore(
      state: makeState(
        sessionID: sessionID,
        revision: 1,
        backgroundAgentStatus: .approvalRequired,
        serviceOperation: .fail(code: "register-denied", message: "Registration denied")
      )
    )
    let runtime = try TestControlRuntime(store: store, participant: .app)
    let service = TestControlAdapters.backgroundAgentService(
      mode: .controlled(runtime)
    ) {
      RecordingManagedService()
    }

    expect(service.status) == .requiresApproval
    expect { try service.register() }.to(
      throwError(
        TestControlOperationError(
          code: "register-denied",
          message: "Registration denied"
        )
      )
    )

    let events = try store.loadEvents(for: .app)
    expect(events.map(\.payload)).to(
      contain(
        .serviceMutation(
          service: .backgroundAgent,
          operation: .register,
          result: .fail(code: "register-denied", message: "Registration denied")
        )
      )
    )
  }

  func testControlledHardwareReturnsConfiguredValuesAndRecordsEveryOperation() throws {
    let sessionID = UUID()
    let store = try makeStore(state: makeState(sessionID: sessionID, revision: 2))
    let runtime = try TestControlRuntime(store: store, participant: .agent)
    let hardware = ControlledFanHardware(runtime: runtime)

    let batch = hardware.readAndApply(
      fanCount: 2,
      tempKeys: ["TC0P", "TG0P"],
      setFans: [(index: 1, rpm: 4_200)],
      autoFans: [0],
      priority: 50
    )
    let ownership = try hardware.getOwnership()
    try hardware.setFanRPM(1, rpm: 4_500, priority: 75)
    try hardware.setFanAuto(0, priority: 25)

    expect(batch.temps) == ["TC0P": 72, "TG0P": 61]
    expect(batch.fans).to(haveCount(2))
    expect(batch.fans[0].actualRPM) == 2_100
    expect(batch.fans[0].manualMode) == false
    expect(batch.fans[1].targetRPM) == 3_400
    expect(batch.fans[1].manualMode) == true
    expect(ownership) == [
      AgentOwnershipEntry(
        id: 1,
        fanIndex: 1,
        clientName: "FanCurveAgent",
        priority: 50,
        ageSeconds: 0
      )
    ]

    let payloads = try store.loadEvents(for: .agent).map(\.payload)
    expect(payloads).to(contain(.hardwareRead(operation: .fanBatch)))
    expect(payloads).to(contain(.hardwareRead(operation: .ownership)))
    expect(payloads).to(contain(.fanWrite(fanIndex: 1, rpm: 4_200, priority: 50)))
    expect(payloads).to(contain(.fanAutoReset(fanIndex: 0)))
    expect(payloads).to(contain(.fanWrite(fanIndex: 1, rpm: 4_500, priority: 75)))
  }

  func testControlledHardwareFailsClosedForConfiguredBatchAndCommandFailures() throws {
    let sessionID = UUID()
    let store = try makeStore(
      state: makeState(
        sessionID: sessionID,
        revision: 3,
        hardwareOperation: .fail(code: "smc-offline", message: "SMC unavailable")
      )
    )
    let runtime = try TestControlRuntime(store: store, participant: .agent)
    let hardware = ControlledFanHardware(runtime: runtime)

    let batch = hardware.readAndApply(
      fanCount: 2,
      tempKeys: ["TC0P"],
      setFans: [(index: 1, rpm: 4_200)],
      autoFans: [0],
      priority: 50
    )

    expect(batch.fans).to(beEmpty())
    expect(batch.temps).to(beEmpty())
    expect {
      try hardware.getOwnership()
    }.to(
      throwError(
        TestControlOperationError(code: "smc-offline", message: "SMC unavailable")
      )
    )
    expect {
      try hardware.setFanRPM(1, rpm: 4_500, priority: nil)
    }.to(
      throwError(
        TestControlOperationError(code: "smc-offline", message: "SMC unavailable")
      )
    )
    expect {
      try hardware.setFanAuto(0, priority: nil)
    }.to(
      throwError(
        TestControlOperationError(code: "smc-offline", message: "SMC unavailable")
      )
    )
  }

  func testRuntimeTreatsEqualRevisionAsIdempotentAndRejectsLowerRevision() throws {
    let sessionID = UUID()
    let initialState = makeState(sessionID: sessionID, revision: 5)
    let store = try makeStore(state: initialState)
    let runtime = try TestControlRuntime(store: store, participant: .app)
    let initialAcknowledgment = try store.loadAcknowledgment(for: .app)

    expect(try runtime.refresh()) == initialState
    expect(try store.loadAcknowledgment(for: .app)) == initialAcknowledgment

    let regressedStateData = try TestControlCodec.encode(
      makeState(sessionID: sessionID, revision: 4)
    )
    try regressedStateData.write(to: store.controlURL, options: .atomic)
    expect { try runtime.refresh() }.to(
      throwError(TestControlError.revisionNotIncreasing(current: 5, proposed: 4))
    )
    expect(try store.loadEvents(for: .app).map(\.payload)).to(
      contain(.revisionRejected(applied: 5, proposed: 4))
    )
    let evidenceDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "FanCurveRegressedEvidence-\(UUID().uuidString)",
        isDirectory: true
      )
    temporaryDirectories.append(evidenceDirectory)
    try store.exportEvidence(to: evidenceDirectory)
    let exportedStore = try TestControlSessionStore.open(at: evidenceDirectory)
    expect(try exportedStore.loadEvents(for: .app).map(\.payload)).to(
      contain(.revisionRejected(applied: 5, proposed: 4))
    )

    let recoveredState = makeState(sessionID: sessionID, revision: 6)
    try TestControlCodec.encode(recoveredState).write(
      to: store.controlURL,
      options: .atomic
    )
    expect(try runtime.refresh()) == recoveredState
    expect(try store.loadAcknowledgment(for: .app)?.revision) == 6
  }
}

// MARK: - Runtime persistence failures

extension TestControlAdapterTests {
  func testRuntimeRetriesEqualRevisionAcknowledgmentAfterWriteFailure() throws {
    let sessionID = UUID()
    let writeProbe = TestControlAtomicWriteProbe(
      failingAcknowledgmentRevision: 2
    )
    let operations = TestControlStoreOperations(
      atomicWrite: { data, url in
        try writeProbe.write(data, to: url)
      },
      synchronize: TestControlStoreOperations.live.synchronize
    )
    let store = try makeStore(
      state: makeState(sessionID: sessionID, revision: 1),
      operations: operations
    )
    let runtime = try TestControlRuntime(store: store, participant: .app)
    runtime.stopMonitoring()
    let proposedState = makeState(sessionID: sessionID, revision: 2)
    try store.apply(proposedState)

    expect { try runtime.refresh() }.to(
      throwError(TestControlAdapterTestError.acknowledgmentWrite)
    )
    expect(try runtime.refresh()) == proposedState
    expect(try store.loadAcknowledgment(for: .app)?.revision) == 2
    expect(writeProbe.failingRevisionAttemptCount) == 2
  }

  func testFaultEffectIsSuppressedWhenEventSynchronizationFails() throws {
    let sessionID = UUID()
    let operations = TestControlStoreOperations(
      atomicWrite: TestControlStoreOperations.live.atomicWrite
    ) { _ in
      throw TestControlAdapterTestError.synchronization
    }
    let store = try makeStore(
      state: makeState(
        sessionID: sessionID,
        revision: 1,
        xpcFault: .interruption
      ),
      operations: operations
    )
    let runtime = try TestControlRuntime(store: store, participant: .agent)
    runtime.stopMonitoring()
    let observation = TestControlBooleanObservation()
    let controller = TestControlAgentXPCFaultController(
      mode: .controlled(runtime)
    ) { _ in
      observation.record()
    }

    expect(controller.consumeFault(at: .currentState)) == .inactive
    expect(observation.value) == false
  }

  func testAppAndAgentAcknowledgeANewerRevisionWithoutAnAdapterOperation() throws {
    let sessionID = UUID()
    let store = try makeStore(state: makeState(sessionID: sessionID, revision: 7))
    let activation = TestControlActivation.controlled(
      sessionID: sessionID,
      directory: store.directory
    )
    let appMode = try TestControlRuntimeMode.resolve(
      participant: .app,
      activation: activation
    )
    let agentMode = try TestControlRuntimeMode.resolve(
      participant: .agent,
      activation: activation
    )

    try store.apply(makeState(sessionID: sessionID, revision: 8))

    expect(
      try store.waitForAcknowledgment(
        participant: .app,
        revision: 8,
        timeout: 1
      ).revision
    ) == 8
    expect(
      try store.waitForAcknowledgment(
        participant: .agent,
        revision: 8,
        timeout: 1
      ).revision
    ) == 8
    withExtendedLifetime((appMode, agentMode)) {
      _ = appMode
    }
  }

  func testCompositionUsesProductionOnlyWhenControlEnvironmentIsAbsent() async throws {
    var serviceFactoryCount = 0
    var hardwareFactoryCount = 0
    let productionMode = try TestControlRuntimeMode.resolve(
      participant: .agent,
      activation: .production
    )

    let service = AgentTestControlAdapters.helperService(mode: productionMode) {
      serviceFactoryCount += 1
      return RecordingManagedService()
    }
    let hardware = AgentTestControlAdapters.fanHardware(mode: productionMode) {
      hardwareFactoryCount += 1
      return RecordingControlledFallbackHardware()
    }
    let batch = await hardware.readAndApply(fanCount: 0, tempKeys: [])

    expect(service.status) == .enabled
    expect(batch.fans).to(beEmpty())
    expect(serviceFactoryCount) == 1
    expect(hardwareFactoryCount) == 1
  }

  func testRefusedCompositionNeverConstructsProductionAndFailsClosed() async throws {
    var serviceFactoryCount = 0
    var hardwareFactoryCount = 0
    let refusedMode = try TestControlRuntimeMode.resolve(
      participant: .agent,
      activation: .refused(path: "/invalid/control/session")
    )

    let service = AgentTestControlAdapters.helperService(mode: refusedMode) {
      serviceFactoryCount += 1
      return RecordingManagedService()
    }
    let hardware = AgentTestControlAdapters.fanHardware(mode: refusedMode) {
      hardwareFactoryCount += 1
      return RecordingControlledFallbackHardware()
    }
    let batch = await hardware.readAndApply(fanCount: 2, tempKeys: ["TC0P"])

    expect(service.status) == .unknown(rawValue: -1)
    expect { try service.register() }.to(
      throwError(TestControlRefusalError(path: "/invalid/control/session"))
    )
    expect(batch.fans).to(beEmpty())
    let rpmError = await captureError {
      try await hardware.setFanRPM(0, rpm: 3_000, priority: nil)
    }
    expect(rpmError).to(
      matchError(TestControlRefusalError(path: "/invalid/control/session"))
    )
    expect(serviceFactoryCount) == 0
    expect(hardwareFactoryCount) == 0
  }

}

// MARK: - TestControlAdapterTests

extension TestControlAdapterTests {
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

  func makeStore(
    state: TestControlState,
    operations: TestControlStoreOperations = .live
  ) throws -> TestControlSessionStore {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "FanCurveControlledAdapters-\(UUID().uuidString)",
        isDirectory: true
      )
    temporaryDirectories.append(directory)
    return try TestControlSessionStore.initialize(
      at: directory,
      initialState: state,
      operations: operations
    )
  }

  private func makeState(
    sessionID: UUID,
    revision: UInt64,
    backgroundAgentStatus: TestManagedServiceStatus = .enabled,
    serviceOperation: TestOperationDirective = .succeed,
    hardwareOperation: TestOperationDirective = .succeed,
    xpcFault: TestXPCFault = .noFault
  ) -> TestControlState {
    TestControlState(
      sessionID: sessionID,
      revision: revision,
      services: TestServiceState(
        backgroundAgentStatus: backgroundAgentStatus,
        helperStatus: .enabled,
        nextOperation: serviceOperation
      ),
      hardware: TestHardwareState(
        sensorTemperatures: [
          TestSensorTemperature(name: "TC0P", temperatureC: 72),
          TestSensorTemperature(name: "TG0P", temperatureC: 61),
        ],
        fanReadings: [
          TestFanReading(
            fanIndex: 0,
            name: "Left Fan",
            actualRPM: 2_100,
            targetRPM: 2_200,
            minimumRPM: 1_200,
            maximumRPM: 5_800,
            isAutomatic: true
          ),
          TestFanReading(
            fanIndex: 1,
            name: "Right Fan",
            actualRPM: 3_300,
            targetRPM: 3_400,
            minimumRPM: 1_300,
            maximumRPM: 5_900,
            isAutomatic: false
          ),
        ],
        ownership: [
          TestFanOwnership(
            fanIndex: 1,
            processName: "FanCurveAgent",
            priority: 50
          )
        ],
        cpuLoadPercent: 42,
        gpuLoadPercent: 18,
        runtimeFlags: TestRuntimeFlags(
          helperReachable: true,
          telemetryStale: false
        ),
        nextOperation: hardwareOperation
      ),
      xpcFault: xpcFault
    )
  }
}

// MARK: - TestControlAdapterTestError

private enum TestControlAdapterTestError: Error, Equatable {
  case acknowledgmentWrite
  case synchronization
}

// MARK: - TestControlAtomicWriteProbe

private final class TestControlAtomicWriteProbe: @unchecked Sendable {
  private let lock = NSLock()
  private let failingAcknowledgmentRevision: TestControlRevision
  private var storedFailingRevisionAttemptCount = 0

  init(failingAcknowledgmentRevision: UInt64) {
    self.failingAcknowledgmentRevision = TestControlRevision(
      failingAcknowledgmentRevision
    )
  }

  var failingRevisionAttemptCount: Int {
    lock.lock()
    let count = storedFailingRevisionAttemptCount
    lock.unlock()
    return count
  }

  func write(_ data: Data, to url: URL) throws {
    var isTargetAcknowledgment = false
    if url.lastPathComponent == TestControlFile.acknowledgment(for: .app) {
      let acknowledgment = try TestControlCodec.decode(
        TestControlAcknowledgment.self,
        from: data
      )
      isTargetAcknowledgment =
        acknowledgment.revision == failingAcknowledgmentRevision
    }
    if isTargetAcknowledgment {
      lock.lock()
      storedFailingRevisionAttemptCount += 1
      let shouldFail = storedFailingRevisionAttemptCount == 1
      lock.unlock()
      if shouldFail {
        throw TestControlAdapterTestError.acknowledgmentWrite
      }
    }
    try data.write(to: url, options: [.atomic])
  }
}
