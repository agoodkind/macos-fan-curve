//
//  FanHardware.swift
//  FanCurveAgent
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation

struct FanHardwareBatchRead: Sendable {
  let fans: [FanInfo]
  let temps: [String: Float]
}

// MARK: - SystemHelperIdentityRequestError

enum SystemHelperIdentityRequestError: LocalizedError, Sendable {
  case unsupported

  var errorDescription: String? {
    "System Helper lifecycle operations are unavailable"
  }
}

// MARK: - FanHardware

/// The agent's single seam onto fan and sensor hardware. Refines
/// `SMCKeyDiscovering` because enumerating the machine's real SMC key set
/// is another read over the same privileged-helper channel, so key
/// discovery stays inside the injected port rather than reaching around it.
protocol FanHardware: SMCKeyDiscovering {
  func shutdown()

  func getHelperIdentity() async throws -> SystemHelperIdentity
  func probeLegacyHelperReachability() async throws
  func resetAllDiscoveredFansToAuto() async throws

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
  func getHelperIdentity() async throws -> SystemHelperIdentity {
    await Task.yield()
    throw SystemHelperIdentityRequestError.unsupported
  }

  func probeLegacyHelperReachability() async throws {
    await Task.yield()
    throw SystemHelperIdentityRequestError.unsupported
  }

  func resetAllDiscoveredFansToAuto() async throws {
    await Task.yield()
    throw SystemHelperIdentityRequestError.unsupported
  }

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
