//
//  AgentServiceMutationResult.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import Foundation

struct AgentServiceMutationResult: Sendable {
    let statusBefore: String
    let statusAfterUnregister: String?
    let statusAfterRegister: String?
    let errorDescription: String?
}

struct HelperServiceMutationResult: Sendable {
    let statusBefore: String
    let statusAfterRegister: String?
    let errorDescription: String?
}
