//
//  SystemHelperRuntimeState.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-04.
//  Copyright © 2026, all rights reserved.
//

import Foundation

struct SystemHelperIdentity: Codable, Equatable, Sendable {
  let version: String
  let build: String
  let commit: String
  let executableHash: String
  let protocolVersion: UInt
}

// MARK: - SystemHelperOperation

enum SystemHelperOperation: String, Codable, Equatable, Sendable {
  case automaticUpdate = "automatic_update"
  case forcedRepair = "forced_repair"
}

// MARK: - SystemHelperFailureStage

enum SystemHelperFailureStage: String, Codable, Equatable, Sendable {
  case disconnect
  case fanReset = "fan_reset"
  case identityVerification = "identity_verification"
  case preflight
  case reconnect
  case register
  case unregister
}

// MARK: - SystemHelperFailure

struct SystemHelperFailure: Codable, Equatable, Sendable {
  let operation: SystemHelperOperation
  let stage: SystemHelperFailureStage
  let reason: String
  let recovery: String
}

// MARK: - SystemHelperRuntimeState

enum SystemHelperRuntimeState: Codable, Equatable, Sendable {
  case approvalRequired
  case checking
  case outdated(active: SystemHelperIdentity?, bundled: SystemHelperIdentity)
  case registrationNeedsRepair(reason: String)
  case repairFailed(
    active: SystemHelperIdentity?,
    bundled: SystemHelperIdentity?,
    failure: SystemHelperFailure
  )
  case running(active: SystemHelperIdentity)
  case unavailable(reason: String)
  case updating(active: SystemHelperIdentity?, bundled: SystemHelperIdentity)

  var activeIdentity: SystemHelperIdentity? {
    switch self {
    case .running(let active):
      active
    case .updating(let active, _), .outdated(let active, _), .repairFailed(let active, _, _):
      active
    case .checking, .registrationNeedsRepair, .approvalRequired, .unavailable:
      nil
    }
  }

  var setupRequirement: RuntimeServiceRequirement {
    switch self {
    case .checking, .running, .updating, .outdated:
      .satisfied
    case .approvalRequired:
      .approvalRequired
    case .registrationNeedsRepair, .repairFailed, .unavailable:
      .required
    }
  }

  var permitsFanControl: Bool {
    if case .running = self {
      return true
    }
    return false
  }
}
