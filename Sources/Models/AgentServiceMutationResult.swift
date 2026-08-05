//
//  AgentServiceMutationResult.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026, all rights reserved.
//

import Foundation

struct AgentServiceMutationResult: Sendable, Equatable {
  let statusBefore: ManagedServiceStatus
  let statusAfterUnregister: ManagedServiceStatus?
  let statusAfterRegister: ManagedServiceStatus?
  let errorDescription: String?
}
