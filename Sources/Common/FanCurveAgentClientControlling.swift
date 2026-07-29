//
//  FanCurveAgentClientControlling.swift
//  FanCurve
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - FanCurveAgentClientGate

enum FanCurveAgentClientGate: Sendable, Equatable {
  case allowed
  case refused(String)
}

// MARK: - FanCurveAgentClientControlEvent

enum FanCurveAgentClientControlEvent: Sendable {
  case commandRejected
  case commandReplyMalformed
  case connected
  case connecting
  case connectionAttemptGated
  case disconnected
  case initialStateRejected
  case reconnectScheduled
  case runtimeEventAccepted
  case runtimeEventRejected
}

// MARK: - FanCurveAgentClientControlling

protocol FanCurveAgentClientControlling: Sendable {
  func connectionGate() -> FanCurveAgentClientGate
  func consumeReconnectFault() -> Bool
  func recordCommand(_ command: AgentCommand)
  func recordEvent(_ event: FanCurveAgentClientControlEvent)
}

// MARK: - ProductionAgentClientControl

struct ProductionAgentClientControl: FanCurveAgentClientControlling {
  func connectionGate() -> FanCurveAgentClientGate {
    .allowed
  }

  func consumeReconnectFault() -> Bool {
    false
  }

  func recordCommand(_ command: AgentCommand) {
    _ = command
  }

  func recordEvent(_ event: FanCurveAgentClientControlEvent) {
    _ = event
  }
}
