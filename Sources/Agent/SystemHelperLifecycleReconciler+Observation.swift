//
//  SystemHelperLifecycleReconciler+Observation.swift
//  FanCurveAgent
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-04.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - SystemHelperLifecycleReconciler

extension SystemHelperLifecycleReconciler {
  func observeActiveHelper() async throws -> SystemHelperIdentityObservation {
    try Task.checkCancellation()
    do {
      return .identity(try await fanHardware.getHelperIdentity())
    } catch {
      let identityFailure = error.localizedDescription
      try Task.checkCancellation()
      do {
        try await fanHardware.probeLegacyHelperReachability()
        return .legacyReachable
      } catch {
        try Task.checkCancellation()
        let reason =
          "System Helper identity failed: \(identityFailure). "
          + "Legacy probe failed: \(error.localizedDescription)"
        return .unreachable(reason: reason)
      }
    }
  }
}
