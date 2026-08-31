//
//  TestControlContractTests.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

@testable import FanCurveModels

final class TestControlContractTests: XCTestCase {
  private var temporaryDirectories: [URL] = []

  override func setUpWithError() throws {
    try super.setUpWithError()
    temporaryDirectories.removeAll()
  }

  override func tearDownWithError() throws {
    for directory in temporaryDirectories
    where FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
    temporaryDirectories.removeAll()
    try super.tearDownWithError()
  }

  func testUnsupportedSchemaCannotOpenAsAControlSession() throws {
    let directory = try makeTemporaryDirectory()
    let controlURL = directory.appendingPathComponent("control.json")
    let state = makeState(sessionID: UUID(), revision: 1)
    let encodedState = try XCTUnwrap(
      String(
        data: TestControlCodec.encode(state),
        encoding: .utf8
      )
    )
    let unsupportedState = encodedState.replacingOccurrences(
      of: #""schemaVersion":1"#,
      with: #""schemaVersion":2"#
    )
    try Data(unsupportedState.utf8).write(to: controlURL, options: .atomic)

    expect {
      try TestControlSessionStore.open(at: directory)
    }.to(throwError(TestControlError.unsupportedSchemaVersion(2)))
  }

  func testOperationDirectivePreservesControlledFailureDetails() throws {
    let directive = TestOperationDirective.fail(
      code: "helper_unavailable",
      message: "The controlled helper is unavailable"
    )

    let data = try TestControlCodec.encode(directive)
    let decoded = try TestControlCodec.decode(
      TestOperationDirective.self,
      from: data
    )

    expect(decoded) == directive
  }

  func testApplyRejectsLowerRevisionAndAtomicallyReplacesControlState() throws {
    let directory = try makeTemporaryDirectory()
    let sessionID = UUID()
    let initialState = makeState(sessionID: sessionID, revision: 2)
    let store = try TestControlSessionStore.initialize(
      at: directory,
      initialState: initialState
    )
    let controlURL = directory.appendingPathComponent("control.json")
    let originalHandle = try FileHandle(forReadingFrom: controlURL)
    addTeardownBlock {
      try originalHandle.close()
    }

    expect {
      try store.apply(self.makeState(sessionID: sessionID, revision: 1))
    }.to(throwError(TestControlError.revisionNotIncreasing(current: 2, proposed: 1)))

    try store.apply(makeState(sessionID: sessionID, revision: 3))

    let currentState = try store.loadState()
    expect(currentState.revision) == 3

    try originalHandle.seek(toOffset: 0)
    let originalData = try XCTUnwrap(try originalHandle.readToEnd())
    let originalState = try JSONDecoder().decode(TestControlState.self, from: originalData)
    expect(originalState.revision) == 2
  }

  func testParticipantsWriteSeparateAcknowledgmentFiles() throws {
    let directory = try makeTemporaryDirectory()
    let sessionID = UUID()
    let store = try TestControlSessionStore.initialize(
      at: directory,
      initialState: makeState(sessionID: sessionID, revision: 4)
    )

    try store.writeAcknowledgment(
      TestControlAcknowledgment(
        sessionID: sessionID,
        revision: 4,
        participant: .app
      )
    )
    try store.writeAcknowledgment(
      TestControlAcknowledgment(
        sessionID: sessionID,
        revision: 4,
        participant: .agent
      )
    )

    let appURL = directory.appendingPathComponent("app.ack.json")
    let agentURL = directory.appendingPathComponent("agent.ack.json")
    expect(FileManager.default.fileExists(atPath: appURL.path)) == true
    expect(FileManager.default.fileExists(atPath: agentURL.path)) == true
    expect(try store.loadAcknowledgment(for: .app)?.participant) == .app
    expect(try store.loadAcknowledgment(for: .agent)?.participant) == .agent
  }

  func testParticipantsAppendSeparateJSONLinesEvidenceFiles() throws {
    let directory = try makeTemporaryDirectory()
    let sessionID = UUID()
    let store = try TestControlSessionStore.initialize(
      at: directory,
      initialState: makeState(sessionID: sessionID, revision: 5)
    )
    let appEvent = TestControlEvent(
      sessionID: sessionID,
      revision: 5,
      participant: .app,
      payload: .appToAgentCommand(command: .installOrRepairHelper)
    )
    let agentEvent = TestControlEvent(
      sessionID: sessionID,
      revision: 5,
      participant: .agent,
      payload: .fanWrite(fanIndex: 0, rpm: 2_100, priority: 50)
    )

    try store.appendEvent(appEvent)
    try store.appendEvent(agentEvent)

    let appURL = directory.appendingPathComponent("app.events.jsonl")
    let agentURL = directory.appendingPathComponent("agent.events.jsonl")
    expect(try JSONLines.count(in: appURL)) == 1
    expect(try JSONLines.count(in: agentURL)) == 1
    expect(try store.loadEvents(for: .app)) == [appEvent]
    expect(try store.loadEvents(for: .agent)) == [agentEvent]
  }

  func testWaitAckObservesAConditionUntilTheExplicitTimeout() throws {
    let directory = try makeTemporaryDirectory()
    let sessionID = UUID()
    let store = try TestControlSessionStore.initialize(
      at: directory,
      initialState: makeState(sessionID: sessionID, revision: 6)
    )
    let waitCompleted = expectation(description: "acknowledgment observed")
    let waitStarted = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var waitResult: Result<TestControlAcknowledgment, Error>?

    DispatchQueue.global().async {
      waitStarted.signal()
      waitResult = Result {
        try store.waitForAcknowledgment(
          participant: .agent,
          revision: 6,
          timeout: 1
        )
      }
      waitCompleted.fulfill()
    }

    expect(waitStarted.wait(timeout: .now() + 1)) == .success
    try store.writeAcknowledgment(
      TestControlAcknowledgment(
        sessionID: sessionID,
        revision: 6,
        participant: .agent
      )
    )
    wait(for: [waitCompleted], timeout: 1)
    let acknowledgment = try waitResult?.get()
    expect(acknowledgment?.revision) == 6
  }

  func testWaitEventMatchesParticipantKindAndRevision() throws {
    let directory = try makeTemporaryDirectory()
    let sessionID = UUID()
    let store = try TestControlSessionStore.initialize(
      at: directory,
      initialState: makeState(sessionID: sessionID, revision: 7)
    )
    let event = TestControlEvent(
      sessionID: sessionID,
      revision: 7,
      participant: .agent,
      payload: .fanAutoReset(fanIndex: 1)
    )
    try store.appendEvent(event)

    let observed = try store.waitForEvent(
      participant: .agent,
      kind: .fanAutoReset,
      revision: 7,
      timeout: 0.25
    )

    expect(observed) == event
  }

  func testActivationDistinguishesAbsentValidAndInvalidPaths() throws {
    let directory = try makeTemporaryDirectory()
    let sessionID = UUID()
    _ = try TestControlSessionStore.initialize(
      at: directory,
      initialState: makeState(sessionID: sessionID, revision: 8)
    )
    let invalidDirectory = try makeTemporaryDirectory()

    expect(TestControlActivation.resolve(environment: [:])) == .production
    expect(
      TestControlActivation.resolve(
        environment: ["FANCURVE_TEST_CONTROL_PATH": directory.path]
      )
    ) == .controlled(sessionID: sessionID, directory: directory)
    expect(
      TestControlActivation.resolve(
        environment: ["FANCURVE_TEST_CONTROL_PATH": invalidDirectory.path]
      )
    ) == .refused(path: invalidDirectory.path)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("FanCurveTestControl-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false
    )
    temporaryDirectories.append(directory)
    return directory
  }

  private func makeState(sessionID: UUID, revision: UInt64) -> TestControlState {
    TestControlState(
      sessionID: sessionID,
      revision: revision,
      services: TestServiceState(
        backgroundAgentStatus: .enabled,
        helperStatus: .notRegistered,
        nextOperation: .succeed
      ),
      hardware: TestHardwareState(
        sensorTemperatures: [
          TestSensorTemperature(name: "CPU", temperatureC: 64)
        ],
        fanReadings: [
          TestFanReading(
            fanIndex: 0,
            name: "Left Fan",
            actualRPM: 2_000,
            targetRPM: 2_100,
            minimumRPM: 1_200,
            maximumRPM: 5_800,
            isAutomatic: false
          )
        ],
        ownership: [
          TestFanOwnership(fanIndex: 0, processName: "FanCurveAgent", priority: 50)
        ],
        cpuLoadPercent: 42,
        gpuLoadPercent: 18,
        runtimeFlags: TestRuntimeFlags(
          helperReachable: true,
          telemetryStale: false
        ),
        nextOperation: .succeed
      ),
      xpcFault: .noFault
    )
  }
}

// MARK: - JSONLines

private enum JSONLines {
  static func count(in url: URL) throws -> Int {
    let contents = try String(contentsOf: url, encoding: .utf8)
    return contents.split(separator: "\n").count
  }
}
