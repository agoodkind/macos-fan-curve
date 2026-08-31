//
//  SystemHelperRuntimeState+Agent.swift
//  FanCurveAgent
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - SystemHelperRuntimeState

extension SystemHelperRuntimeState {
  var commandFailureMessage: String {
    switch self {
    case .approvalRequired:
      return "System Helper approval is required"
    case .checking:
      return "System Helper reconciliation did not finish"
    case .outdated:
      return "System Helper is outdated"
    case .registrationNeedsRepair(let reason), .unavailable(let reason):
      return reason
    case .repairFailed(_, _, let failure):
      return failure.reason
    case .running:
      return ""
    case .updating:
      return "System Helper update did not finish"
    }
  }

  var logName: String {
    switch self {
    case .approvalRequired:
      return "approval_required"
    case .checking:
      return "checking"
    case .outdated:
      return "outdated"
    case .registrationNeedsRepair:
      return "registration_needs_repair"
    case .repairFailed:
      return "repair_failed"
    case .running:
      return "running"
    case .unavailable:
      return "unavailable"
    case .updating:
      return "updating"
    }
  }
}
