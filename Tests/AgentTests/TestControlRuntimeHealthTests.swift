//
//  TestControlRuntimeHealthTests.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

private enum RuntimeHealthTestConstants {
  static let revision: UInt64 = 2
  static let fanCount: UInt = 1
  static let snapshotReferenceTime: TimeInterval = 1_000
}

// MARK: - TestControlRuntimeHealthTests

final class TestControlRuntimeHealthTests: XCTestCase {
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

  func testControlledRuntimeFlagsDriveHardwareAvailabilityAndHealthOverrides() async throws {
    let sessionID = UUID()
    let store = try makeStore(state: makeRuntimeHealthState(sessionID: sessionID))
    let runtime = try TestControlRuntime(store: store, participant: .agent)
    let mode = TestControlRuntimeMode.controlled(runtime)
    let hardware = ControlledFanHardware(runtime: runtime)
    let batch = await hardware.readAndApply(
      fanCount: RuntimeHealthTestConstants.fanCount,
      tempKeys: ["TC0P"]
    )
    let provider = try XCTUnwrap(
      AgentTestControlAdapters.runtimeHealthOverrideProvider(mode: mode)
    )
    let snapshotTimestamp = Date(
      timeIntervalSinceReferenceDate: RuntimeHealthTestConstants.snapshotReferenceTime
    )
    let overrides = try XCTUnwrap(provider(snapshotTimestamp))

    expect(batch.fans).to(beEmpty())
    expect(batch.temps).to(beEmpty())
    expect(overrides.ownershipPreempted) == true
    expect(overrides.now.timeIntervalSince(snapshotTimestamp))
      > FanCurveAgentClientConstants.snapshotFreshnessWindow
  }

  private func makeStore(
    state: TestControlState
  ) throws -> TestControlSessionStore {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "FanCurveRuntimeHealth-\(UUID().uuidString)",
        isDirectory: true
      )
    temporaryDirectories.append(directory)
    return try TestControlSessionStore.initialize(
      at: directory,
      initialState: state
    )
  }
}

private func makeRuntimeHealthState(sessionID: UUID) -> TestControlState {
  TestControlState(
    sessionID: sessionID,
    revision: RuntimeHealthTestConstants.revision,
    services: TestServiceState(
      backgroundAgentStatus: .enabled,
      helperStatus: .enabled,
      nextOperation: .succeed
    ),
    hardware: TestHardwareState(
      sensorTemperatures: [],
      fanReadings: [],
      ownership: [],
      cpuLoadPercent: 0,
      gpuLoadPercent: 0,
      runtimeFlags: TestRuntimeFlags(
        helperReachable: false,
        telemetryStale: true,
        ownershipPreempted: true
      ),
      nextOperation: .succeed
    ),
    xpcFault: .noFault
  )
}
