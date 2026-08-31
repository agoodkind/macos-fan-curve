//
//  FanCurveAgentClient+Commands.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - Commands

extension FanCurveAgentClient {
  func setFanControlEnabled(_ enabled: Bool) async throws {
    try await send(.setFanControlEnabled(enabled))
  }

  func setBoostEnabled(_ enabled: Bool) async throws {
    try await send(.setBoostEnabled(enabled))
  }

  func setCurve(points: [CurvePoint], interpolationMode: InterpolationMode) async throws {
    let update = AgentCurveUpdate(points: points, interpolationMode: interpolationMode)
    try await send(.setCurve(update))
  }

  func setApplyInBackground(_ enabled: Bool) async throws {
    try await send(.setApplyInBackground(enabled))
  }

  func installOrRepairHelper() async throws {
    try await send(.installOrRepairHelper)
  }

  func openSystemSettings() async throws {
    try await send(.openSystemSettings)
  }

  func setFanRPM(_ fanIndex: UInt, rpm: Float) async throws {
    let request = AgentFanRPMRequest(fanIndex: fanIndex, rpm: rpm)
    try await send(.requestFanRPM(request))
  }

  func setFanAuto(_ fanIndex: UInt) async throws {
    try await send(.requestFanAuto(fanIndex: fanIndex))
  }

  func getOwnership() async throws -> [AgentOwnershipEntry] {
    let ownershipData = try await performRequest(.ownership)
    guard let ownershipData else {
      throw FanCurveAgentClientError.invalidReply
    }
    do {
      return try JSONDecoder().decode([AgentOwnershipEntry].self, from: ownershipData)
    } catch {
      fanCurveAgentClientLog.error(
        "agent_client.ownership.decode_failed error=\(error.localizedDescription, privacy: .public) recovery=propagate"
      )
      throw error
    }
  }
}
