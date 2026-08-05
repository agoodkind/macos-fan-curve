//
//  TestControlCommandTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

@testable import FanCurveModels

private let testRepositoryURL = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()

private func addTestBuildVersion(to environment: inout [String: String]) {
  environment["MARKETING_VERSION"] = "0.0.0-test"
  environment["CURRENT_PROJECT_VERSION"] = "0"
}

final class TestControlCommandTests: XCTestCase {
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

  func testCommandParserExposesEveryControlCommandWithExplicitWaitTimeouts() throws {
    let sessionPath = "/tmp/fan-curve-control"
    let statePath = "/tmp/state.json"
    let outputPath = "/tmp/evidence"

    expect(
      try FanCurveTestControlCommand.parse(["initialize", "--session", sessionPath])
    ) == .initialize(sessionPath: sessionPath)
    expect(
      try FanCurveTestControlCommand.parse(
        ["apply", "--session", sessionPath, "--state", statePath]
      )
    ) == .apply(sessionPath: sessionPath, statePath: statePath)
    expect(
      try FanCurveTestControlCommand.parse([
        "wait-ack", "--session", sessionPath, "--participant", "app",
        "--revision", "9", "--timeout", "3.5",
      ])
    )
      == .waitAcknowledgment(
        sessionPath: sessionPath,
        wait: TestControlAcknowledgmentWait(
          participant: .app,
          revision: 9,
          timeout: 3.5
        )
      )
    expect(
      try FanCurveTestControlCommand.parse([
        "wait-event", "--session", sessionPath, "--participant", "agent",
        "--kind", "fan_write", "--revision", "9", "--timeout", "4",
      ])
    )
      == .waitEvent(
        sessionPath: sessionPath,
        wait: TestControlEventWait(
          participant: .agent,
          kind: .fanWrite,
          revision: 9,
          timeout: 4
        )
      )
    expect(
      try FanCurveTestControlCommand.parse(
        ["export-evidence", "--session", sessionPath, "--output", outputPath]
      )
    ) == .exportEvidence(sessionPath: sessionPath, outputPath: outputPath)
  }

  func testInitializeCommandCreatesAVersionedUniqueSession() throws {
    let directory = try makeTemporaryDirectory()

    let command = FanCurveTestControlCommand.initialize(
      sessionPath: directory.path
    )
    let output = try command.run()

    let store = try TestControlSessionStore.open(at: directory)
    let state = try store.loadState()
    expect(state.schemaVersion) == .current
    expect(state.revision) == 1
    expect(output).to(contain(state.sessionID.uuidString))
  }

  func testApplyCommandReplacesControlStateWithANewerRevision() throws {
    let directory = try makeTemporaryDirectory()
    let sessionID = UUID()
    let store = try TestControlSessionStore.initialize(
      at: directory,
      initialState: makeState(sessionID: sessionID, revision: 10)
    )
    let stateURL = directory.appendingPathComponent("next-state.json")
    let encodedState = try TestControlCodec.encode(
      makeState(sessionID: sessionID, revision: 11)
    )
    try encodedState.write(to: stateURL, options: .atomic)

    let command = FanCurveTestControlCommand.apply(
      sessionPath: directory.path,
      statePath: stateURL.path
    )
    let output = try command.run()

    expect(try store.loadState().revision) == 11
    expect(output).to(contain("revision=11"))
  }

  func testWaitAckCommandReturnsTheMatchingAcknowledgment() throws {
    let directory = try makeTemporaryDirectory()
    let sessionID = UUID()
    let store = try TestControlSessionStore.initialize(
      at: directory,
      initialState: makeState(sessionID: sessionID, revision: 12)
    )
    try store.writeAcknowledgment(
      TestControlAcknowledgment(
        sessionID: sessionID,
        revision: 12,
        participant: .app
      )
    )

    let command = FanCurveTestControlCommand.waitAcknowledgment(
      sessionPath: directory.path,
      wait: TestControlAcknowledgmentWait(
        participant: .app,
        revision: 12,
        timeout: 0.25
      )
    )
    let output = try command.run()

    expect(output).to(contain("participant=app"))
    expect(output).to(contain("revision=12"))
  }

  func testWaitEventCommandReturnsTheMatchingEvidence() throws {
    let directory = try makeTemporaryDirectory()
    let sessionID = UUID()
    let store = try TestControlSessionStore.initialize(
      at: directory,
      initialState: makeState(sessionID: sessionID, revision: 13)
    )
    let event = TestControlEvent(
      sessionID: sessionID,
      revision: 13,
      participant: .agent,
      payload: .fanAutoReset(fanIndex: 0)
    )
    try store.appendEvent(event)

    let command = FanCurveTestControlCommand.waitEvent(
      sessionPath: directory.path,
      wait: TestControlEventWait(
        participant: .agent,
        kind: .fanAutoReset,
        revision: 13,
        timeout: 0.25
      )
    )
    let output = try command.run()

    expect(output).to(contain("kind=fan_auto_reset"))
    expect(output).to(contain(event.eventID.uuidString))
  }

  func testExportEvidenceCommandPreservesSeparateParticipantFiles() throws {
    let directory = try makeTemporaryDirectory()
    let outputDirectory = try makeTemporaryDirectory()
    let sessionID = UUID()
    let store = try TestControlSessionStore.initialize(
      at: directory,
      initialState: makeState(sessionID: sessionID, revision: 14)
    )
    try store.appendEvent(
      TestControlEvent(
        sessionID: sessionID,
        revision: 14,
        participant: .app,
        payload: .appToAgentCommand(command: .setBoostEnabled)
      )
    )
    try store.appendEvent(
      TestControlEvent(
        sessionID: sessionID,
        revision: 14,
        participant: .agent,
        payload: .hardwareRead(operation: .fanBatch)
      )
    )

    let command = FanCurveTestControlCommand.exportEvidence(
      sessionPath: directory.path,
      outputPath: outputDirectory.path
    )
    _ = try command.run()

    let appEventsURL = outputDirectory.appendingPathComponent("app.events.jsonl")
    let agentEventsURL = outputDirectory.appendingPathComponent("agent.events.jsonl")
    expect(FileManager.default.fileExists(atPath: appEventsURL.path)) == true
    expect(FileManager.default.fileExists(atPath: agentEventsURL.path)) == true
  }

}

// MARK: - Config generation

extension TestControlCommandTests {
  func testGeneratedAgentEnvironmentIncludesOnlyExplicitDebugControlPath() throws {
    let root = try makeTemporaryDirectory()
    let templatesURL = testRepositoryURL.appendingPathComponent(
      "Templates",
      isDirectory: true
    )
    try FileManager.default.copyItem(
      at: templatesURL,
      to: root.appendingPathComponent("Templates", isDirectory: true)
    )
    let controlPath = "/tmp/fan-curve-control&session"

    try runConfigGenerator(
      root: root,
      configuration: "Debug",
      testControlPath: controlPath
    )
    expect(
      try self.generatedAgentEnvironment(in: root)["FANCURVE_TEST_CONTROL_PATH"]
    ) == controlPath
    let generatedURL = root.appendingPathComponent(
      "Generated/FanCurve/Config.generated.swift"
    )
    let generated = try String(contentsOf: generatedURL, encoding: .utf8)
    expect(generated).to(contain(#"let generatedDevelopmentTeam = "H3BMXM4W7H""#))

    try runConfigGenerator(
      root: root,
      configuration: "Release",
      testControlPath: controlPath
    )
    expect(
      try self.generatedAgentEnvironment(in: root)["FANCURVE_TEST_CONTROL_PATH"]
    ) == nil

    try runConfigGenerator(
      root: root,
      configuration: "Debug",
      testControlPath: nil
    )
    expect(
      try self.generatedAgentEnvironment(in: root)["FANCURVE_TEST_CONTROL_PATH"]
    ) == nil
  }

  private func runConfigGenerator(
    root: URL,
    configuration: String,
    testControlPath: String?
  ) throws {
    let process = Process()
    process.executableURL = testRepositoryURL.appendingPathComponent(
      "Scripts/GenerateConfig.swift"
    )
    var environment = ProcessInfo.processInfo.environment
    environment.merge([
      "AGENT_BUNDLE_ID": "io.goodkind.fancurveagent",
      "AGENT_DISPLAY_NAME": "Fan Curve Background Control",
      "AGENT_EXECUTABLE_NAME": "FanCurveAgent",
      "APP_BUNDLE_ID": "io.goodkind.fancurve",
      "APP_DISPLAY_NAME": "Fan Curve",
      "BUNDLE_ID_PREFIX": "io.goodkind",
      "CONFIGURATION": configuration,
      "DEVELOPMENT_TEAM": "H3BMXM4W7H",
      "HELPER_BUNDLE_ID": "io.goodkind.smcfanhelper",
      "HELPER_DISPLAY_NAME": "Fan Curve Hardware Helper",
      "SHARED_SUITE_ID": "io.goodkind.fancurve.shared",
      "SRCROOT": root.path,
      "TARGET_NAME": "FanCurve",
    ]) { _, newValue in newValue }
    addTestBuildVersion(to: &environment)
    environment["FANCURVE_TEST_CONTROL_PATH"] = testControlPath
    process.environment = environment
    let errorPipe = Pipe()
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
    expect(process.terminationStatus) == 0
    expect(errorOutput.isEmpty) == true
  }

  private func generatedAgentEnvironment(in root: URL) throws -> [String: String] {
    let plistURL = root.appendingPathComponent(
      "Generated/FanCurve/agent-launchd.plist"
    )
    let data = try Data(contentsOf: plistURL)
    let plist = try PropertyListDecoder().decode(
      GeneratedLaunchAgentPlist.self,
      from: data
    )
    return plist.environmentVariables ?? [:]
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "FanCurveTestControl-\(UUID().uuidString)",
        isDirectory: true
      )
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
        sensorTemperatures: [],
        fanReadings: [],
        ownership: [],
        cpuLoadPercent: 0,
        gpuLoadPercent: 0,
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

// MARK: - GeneratedLaunchAgentPlist

private struct GeneratedLaunchAgentPlist: Decodable {
  let environmentVariables: [String: String]?

  private enum CodingKeys: String, CodingKey {
    case environmentVariables = "EnvironmentVariables"
  }
}
