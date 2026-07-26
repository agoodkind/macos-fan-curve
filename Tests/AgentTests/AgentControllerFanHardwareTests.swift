//
//  AgentControllerFanHardwareTests.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

final class AgentControllerFanHardwareTests: XCTestCase {
  func testTelemetryReadUsesInjectedFanHardware() async {
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
    let controller = AgentController(fanHardware: hardware)
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

  func testTickCommandsUseInjectedFanHardwareWithExactPriority() async {
    let hardware = RecordingFanHardware()
    let controller = AgentController(fanHardware: hardware)
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
    let controller = AgentController(fanHardware: hardware)

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

  func testResetAllFansToAutoUsesInjectedFanHardwareForEveryFan() async {
    let hardware = RecordingFanHardware()
    let controller = AgentController(fanHardware: hardware)
    controller.cachedFanCount = 3

    await controller.resetAllFansToAuto()

    let request = hardware.singleReadRequest
    expect(request.fanCount) == 3
    expect(request.tempKeys).to(beEmpty())
    expect(request.setFans).to(beEmpty())
    expect(request.autoFans) == [0, 1, 2]
    expect(request.priority) == nil
  }
}

// MARK: - RecordingFanHardware

private final class RecordingFanHardware: FanHardware, @unchecked Sendable {
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
  private var readRequests: [ReadRequest] = []
  private var rpmCommands: [RPMCommand] = []
  private var autoCommands: [AutoCommand] = []
  private var ownershipReads = 0

  init(
    readResult: FanHardwareBatchRead = FanHardwareBatchRead(fans: [], temps: [:]),
    ownership: [AgentOwnershipEntry] = []
  ) {
    self.readResult = readResult
    self.ownership = ownership
  }

  func shutdown() {
    // The test double has no external connection to close.
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
