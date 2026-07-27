//
//  FanHardware.swift
//  FanCurveAgent
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation

struct FanHardwareBatchRead: Sendable {
  let fans: [FanInfo]
  let temps: [String: Float]
}

// MARK: - FanHardware

protocol FanHardware: Sendable {
  func shutdown()

  func readAndApply(
    fanCount: UInt,
    tempKeys: [String],
    setFans: [(index: UInt, rpm: Float)],
    autoFans: [UInt],
    priority: Int?
  ) async -> FanHardwareBatchRead

  func getOwnership() async throws -> [AgentOwnershipEntry]

  func setFanRPM(
    _ index: UInt,
    rpm: Float,
    priority: Int?
  ) async throws

  func setFanAuto(
    _ index: UInt,
    priority: Int?
  ) async throws
}

// MARK: - FanHardware

extension FanHardware {
  func readAndApply(
    fanCount: UInt,
    tempKeys: [String]
  ) async -> FanHardwareBatchRead {
    await readAndApply(
      fanCount: fanCount,
      tempKeys: tempKeys,
      setFans: [],
      autoFans: [],
      priority: nil
    )
  }

  func readAndApply(
    fanCount: UInt,
    tempKeys: [String],
    autoFans: [UInt]
  ) async -> FanHardwareBatchRead {
    await readAndApply(
      fanCount: fanCount,
      tempKeys: tempKeys,
      setFans: [],
      autoFans: autoFans,
      priority: nil
    )
  }
}
