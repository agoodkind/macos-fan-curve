//
//  SystemHelperReconcileTiming.swift
//  FanCurveAgent
//
//  Created by Codex <noreply@openai.com> on 2026-08-04.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - SystemHelperReconcileTiming

enum SystemHelperReconcileTiming {
  static let verificationPollMilliseconds: Int64 = 250
  static let verificationTimeoutSeconds: Int64 = 10
  static let verificationPollInterval = Duration.milliseconds(
    verificationPollMilliseconds
  )
  static let verificationTimeout = Duration.seconds(verificationTimeoutSeconds)
}

// MARK: - SystemHelperFailureContext

struct SystemHelperFailureContext {
  let operation: SystemHelperOperation
  let activeIdentity: SystemHelperIdentity?
  let bundledIdentity: SystemHelperIdentity?
}

// MARK: - SystemHelperReconcileResult

struct SystemHelperReconcileResult: Sendable {
  let state: SystemHelperRuntimeState
  let registrationMutated: Bool
}

// MARK: - ActiveSystemHelperReconciliation

struct ActiveSystemHelperReconciliation {
  let id: UUID
  let task: Task<SystemHelperReconcileResult, Never>
  var waiterIDs: Set<UUID>
}

// MARK: - SystemHelperReconcileTrigger

enum SystemHelperReconcileTrigger: Equatable, Sendable {
  case forcedRepair
  case reconnect
  case startup

  var operation: SystemHelperOperation {
    if self == .forcedRepair {
      return .forcedRepair
    }
    return .automaticUpdate
  }
}

// MARK: - SystemHelperIdentityObservation

extension SystemHelperIdentityObservation {
  var activeIdentity: SystemHelperIdentity? {
    guard case .identity(let identity) = self else { return nil }
    return identity
  }

  var isReachable: Bool {
    switch self {
    case .identity, .legacyReachable:
      return true
    case .unreachable:
      return false
    }
  }
}

// MARK: - SystemHelperControllerLifecycleGating

protocol SystemHelperControllerLifecycleGating: Sendable {
  func pause()
  func resume()
}
