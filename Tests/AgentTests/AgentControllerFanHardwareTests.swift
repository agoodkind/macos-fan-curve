//
//  AgentControllerFanHardwareTests.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import OSLog
import XCTest

final class AgentControllerFanHardwareTests: XCTestCase {
  private var defaultsSuiteName = ""
  private var isolatedDefaults: UserDefaults?
  private var isolatedSharedConfig: SharedConfig?

  override func setUpWithError() throws {
    try super.setUpWithError()
    defaultsSuiteName = "io.goodkind.fancurve.agent-tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
    defaults.removePersistentDomain(forName: defaultsSuiteName)
    isolatedDefaults = defaults
    isolatedSharedConfig = SharedConfig(defaults: defaults)
  }

  override func tearDownWithError() throws {
    isolatedDefaults?.removePersistentDomain(forName: defaultsSuiteName)
    isolatedSharedConfig = nil
    isolatedDefaults = nil
    defaultsSuiteName = ""
    try super.tearDownWithError()
  }

  func testTelemetryReadUsesInjectedFanHardware() async throws {
    let fan = FanInfo(
      actualRPM: 2_500,
      targetRPM: 2_700,
      minRPM: 2_000,
      maxRPM: 6_000,
      manualMode: true
    )
    let hardware = RecordingFanHardware(
      readResult: FanHardwareBatchRead(
        fans: [fan],
        temps: ["TC0P": 72]
      )
    )
    let controller = try makeController(fanHardware: hardware)
    controller.cachedFanCount = 1

    let telemetry = await controller.readTickTelemetry()

    let request = hardware.singleReadRequest
    expect(request.fanCount) == 1
    expect(request.tempKeys) == controller.tempKeys
    expect(request.setFans).to(beEmpty())
    expect(request.autoFans).to(beEmpty())
    expect(request.priority) == nil
    expect(telemetry.result.fans.first?.actualRPM) == 2_500
    expect(telemetry.result.temps["TC0P"]) == 72
  }

  func testTelemetryReadClearsLastErrorWithoutPublishingLiveness() async throws {
    let hardware = RecordingFanHardware()
    let controller = try makeController(fanHardware: hardware)
    let defaults = try XCTUnwrap(isolatedDefaults)
    defaults.set("existing diagnostic", forKey: SharedConfigKeys.agentLastError)

    _ = await controller.readTickTelemetry()

    expect(defaults.string(forKey: SharedConfigKeys.agentLastError)) == nil
    // Liveness belongs to the heartbeat cadence, so a read that stalls or
    // returns nothing must not be what refreshes the PID and timestamp.
    expect(defaults.integer(forKey: SharedConfigKeys.agentPID)) == 0
    expect(defaults.double(forKey: SharedConfigKeys.agentLastTick)) == 0
    expect(defaults.string(forKey: SharedConfigKeys.agentExecutableHash)) == nil
  }

  func testHeartbeatPublishesLivenessToInjectedSharedConfig() throws {
    let hardware = RecordingFanHardware()
    let controller = try makeController(fanHardware: hardware)
    let defaults = try XCTUnwrap(isolatedDefaults)

    controller.publishHeartbeat()

    expect(defaults.integer(forKey: SharedConfigKeys.agentPID))
      == Int(ProcessInfo.processInfo.processIdentifier)
    expect(defaults.double(forKey: SharedConfigKeys.agentLastTick)) > 0
    expect(defaults.string(forKey: SharedConfigKeys.agentExecutableHash)) != nil
  }

  func testTickCommandsUseInjectedFanHardwareWithExactPriority() async throws {
    let hardware = RecordingFanHardware()
    let controller = try makeController(fanHardware: hardware)
    let actions = AgentControllerTickTypes.FanActions(
      setFans: [(index: 1, rpm: 4_200)],
      autoFans: [0],
      tickPriority: 50,
      assistSummary: ""
    )

    await controller.applyFanActions(actions)

    let request = hardware.singleReadRequest
    expect(request.fanCount) == 0
    expect(request.tempKeys).to(beEmpty())
    expect(request.setFans).to(haveCount(1))
    expect(request.setFans.first?.index) == 1
    expect(request.setFans.first?.rpm) == 4_200
    expect(request.autoFans) == [0]
    expect(request.priority) == 50
  }

  func testManualCommandsAndOwnershipUseInjectedFanHardware() async throws {
    let ownership = [
      AgentOwnershipEntry(
        id: 1,
        fanIndex: 1,
        clientName: "io.goodkind.test",
        priority: 75,
        ageSeconds: 2
      )
    ]
    let hardware = RecordingFanHardware(ownership: ownership)
    let controller = try makeController(fanHardware: hardware)

    try await controller.setFanRPM(1, rpm: 4_800)
    try await controller.setFanAuto(0)
    let result = try await controller.getOwnership()

    expect(hardware.singleRPMCommand.index) == 1
    expect(hardware.singleRPMCommand.rpm) == 4_800
    expect(hardware.singleRPMCommand.priority) == nil
    expect(hardware.singleAutoCommand.index) == 0
    expect(hardware.singleAutoCommand.priority) == nil
    expect(result) == ownership
    expect(hardware.ownershipReadCount) == 1
  }

  func testSuccessfulManualCommandsWriteCompletionLogs() async throws {
    let logStore = try OSLogStore(scope: .currentProcessIdentifier)
    let logPosition = logStore.position(date: Date())
    let hardware = RecordingFanHardware()
    let controller = try makeController(fanHardware: hardware)

    try await controller.setFanRPM(1, rpm: 4_800)
    try await controller.setFanAuto(0)

    var messages: [String] = []
    for entry in try logStore.getEntries(at: logPosition) {
      guard let logEntry = entry as? OSLogEntryLog else { continue }
      messages.append(logEntry.composedMessage)
    }
    expect(messages.contains { $0.contains("agent.hardware.rpm.succeeded fan=1 rpm=4800") })
      == true
    expect(messages.contains { $0.contains("agent.hardware.auto.succeeded fan=0") })
      == true
  }

  func testResetAllFansToAutoUsesInjectedFanHardwareForEveryFan() async throws {
    let hardware = RecordingFanHardware()
    let controller = try makeController(fanHardware: hardware)
    controller.cachedFanCount = 3

    await controller.resetAllFansToAuto()

    let request = hardware.singleReadRequest
    expect(request.fanCount) == 3
    expect(request.tempKeys).to(beEmpty())
    expect(request.setFans).to(beEmpty())
    expect(request.autoFans) == [0, 1, 2]
    expect(request.priority) == nil
  }

  private func makeController(
    fanHardware: any FanHardware
  ) throws -> AgentController {
    let sharedConfig = try XCTUnwrap(isolatedSharedConfig)
    return AgentController(
      fanHardware: fanHardware,
      sharedConfig: sharedConfig
    )
  }
}

// MARK: - RecordingFanHardware

final class RecordingFanHardware: FanHardware, @unchecked Sendable {
  struct ReadRequest {
    let fanCount: UInt
    let tempKeys: [String]
    let setFans: [(index: UInt, rpm: Float)]
    let autoFans: [UInt]
    let priority: Int?
  }

  struct RPMCommand {
    let index: UInt
    let rpm: Float
    let priority: Int?
  }

  struct AutoCommand {
    let index: UInt
    let priority: Int?
  }

  private let lock = NSLock()
  private let readResult: FanHardwareBatchRead
  private let ownership: [AgentOwnershipEntry]
  private let discoveredKeys: [String]
  private var readRequests: [ReadRequest] = []
  private var rpmCommands: [RPMCommand] = []
  private var autoCommands: [AutoCommand] = []
  private var ownershipReads = 0

  init(
    readResult: FanHardwareBatchRead = FanHardwareBatchRead(fans: [], temps: [:]),
    ownership: [AgentOwnershipEntry] = [],
    discoveredKeys: [String] = []
  ) {
    self.readResult = readResult
    self.ownership = ownership
    self.discoveredKeys = discoveredKeys
  }

  func shutdown() {
    // The test double has no external connection to close.
  }

  /// Defaults to the empty "could not enumerate" answer, which
  /// `SensorKeyResolver` treats as ambiguous and never prunes on, so these
  /// tests keep the controller's full catalog key set.
  func enumerateKeys() async -> [String] {
    await Task.yield()
    return discoveredKeys
  }

  func readAndApply(
    fanCount: UInt,
    tempKeys: [String],
    setFans: [(index: UInt, rpm: Float)],
    autoFans: [UInt],
    priority: Int?
  ) async -> FanHardwareBatchRead {
    await Task.yield()
    lock.withLock {
      readRequests.append(
        ReadRequest(
          fanCount: fanCount,
          tempKeys: tempKeys,
          setFans: setFans,
          autoFans: autoFans,
          priority: priority
        )
      )
    }
    return readResult
  }

  func getOwnership() async throws -> [AgentOwnershipEntry] {
    await Task.yield()
    try Task.checkCancellation()
    lock.withLock {
      ownershipReads += 1
    }
    return ownership
  }

  func setFanRPM(_ index: UInt, rpm: Float, priority: Int?) async throws {
    await Task.yield()
    try Task.checkCancellation()
    lock.withLock {
      rpmCommands.append(RPMCommand(index: index, rpm: rpm, priority: priority))
    }
  }

  func setFanAuto(_ index: UInt, priority: Int?) async throws {
    await Task.yield()
    try Task.checkCancellation()
    lock.withLock {
      autoCommands.append(AutoCommand(index: index, priority: priority))
    }
  }

  var singleReadRequest: ReadRequest {
    lock.lock()
    defer { lock.unlock() }
    expect(self.readRequests).to(haveCount(1))
    return readRequests[0]
  }

  var singleRPMCommand: RPMCommand {
    lock.lock()
    defer { lock.unlock() }
    expect(self.rpmCommands).to(haveCount(1))
    return rpmCommands[0]
  }

  var singleAutoCommand: AutoCommand {
    lock.lock()
    defer { lock.unlock() }
    expect(self.autoCommands).to(haveCount(1))
    return autoCommands[0]
  }

  var ownershipReadCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return ownershipReads
  }
}
