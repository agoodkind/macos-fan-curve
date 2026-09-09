//
//  AgentServiceMutationResult.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026, all rights reserved.
//

import Foundation

struct AgentServiceMutationResult: Sendable, Equatable {
  let statusBefore: ManagedServiceStatus
  let statusAfterUnregister: ManagedServiceStatus?
  let statusAfterRegister: ManagedServiceStatus?
  let errorDescription: String?
  let failureReason: ManagedServiceFailureReason?

  init(
    statusBefore: ManagedServiceStatus,
    statusAfterUnregister: ManagedServiceStatus?,
    statusAfterRegister: ManagedServiceStatus?,
    errorDescription: String?,
    failureReason: ManagedServiceFailureReason? = nil
  ) {
    self.statusBefore = statusBefore
    self.statusAfterUnregister = statusAfterUnregister
    self.statusAfterRegister = statusAfterRegister
    self.errorDescription = errorDescription
    self.failureReason = failureReason
  }

  func errorRequiringRetry(status: ManagedServiceStatus) -> String? {
    if status == .requiresApproval, failureReason == .operationNotPermitted {
      return nil
    }
    return errorDescription
  }
}
