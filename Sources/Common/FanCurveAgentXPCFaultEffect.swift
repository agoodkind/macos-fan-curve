//
//  FanCurveAgentXPCFaultEffect.swift
//  FanCurve
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - FanCurveAgentXPCFaultBoundary

enum FanCurveAgentXPCFaultBoundary: Sendable {
  case command
  case currentState
  case runtimeEvent
}

// MARK: - FanCurveAgentXPCFaultEffect

enum FanCurveAgentXPCFaultEffect: Equatable, Sendable {
  case duplicateEvent
  case inactive
  case invalidateConnection
  case malformedEvent
  case malformedInitialState
  case malformedReply
  case rejectCommand
  case terminateAgent
}

// MARK: - FanCurveAgentXPCFaultControlling

protocol FanCurveAgentXPCFaultControlling: Sendable {
  func consumeFault(
    at boundary: FanCurveAgentXPCFaultBoundary
  ) -> FanCurveAgentXPCFaultEffect
}

// MARK: - ProductionAgentXPCFaultControl

struct ProductionAgentXPCFaultControl: FanCurveAgentXPCFaultControlling {
  func consumeFault(
    at _: FanCurveAgentXPCFaultBoundary
  ) -> FanCurveAgentXPCFaultEffect {
    .inactive
  }
}
