//
//  SystemHelperClassifier.swift
//  FanCurve
//
//  Created by Codex <noreply@openai.com> on 2026-08-04.
//  Copyright © 2026, all rights reserved.
//

import Foundation

enum SystemHelperIdentityObservation: Equatable, Sendable {
  case identity(SystemHelperIdentity)
  case legacyReachable
  case unreachable(reason: String)
}

// MARK: - SystemHelperClassifier

enum SystemHelperClassifier {
  static func classify(
    serviceStatus: ManagedServiceStatus,
    observation: SystemHelperIdentityObservation,
    bundled: SystemHelperIdentity
  ) -> SystemHelperRuntimeState {
    if let inactiveState = classifyInactive(serviceStatus: serviceStatus) {
      return inactiveState
    }
    return classifyEnabled(observation: observation, bundled: bundled)
  }

  static func classifyInactive(
    serviceStatus: ManagedServiceStatus
  ) -> SystemHelperRuntimeState? {
    switch serviceStatus {
    case .requiresApproval:
      return .approvalRequired
    case .notRegistered:
      return .registrationNeedsRepair(reason: "System Helper is not registered")
    case .notFound:
      return .unavailable(reason: "System Helper registration definition was not found")
    case .unknown(let rawValue):
      return .unavailable(reason: "System Helper service status is unknown (\(rawValue))")
    case .enabled:
      return nil
    }
  }

  private static func classifyEnabled(
    observation: SystemHelperIdentityObservation,
    bundled: SystemHelperIdentity
  ) -> SystemHelperRuntimeState {
    switch observation {
    case .identity(let active):
      if active.executableHash == bundled.executableHash {
        return .running(active: active)
      }
      return .outdated(active: active, bundled: bundled)
    case .legacyReachable:
      return .outdated(active: nil, bundled: bundled)
    case .unreachable(let reason):
      return .unavailable(reason: reason)
    }
  }
}
