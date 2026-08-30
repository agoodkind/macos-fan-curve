//
//  AgentCommandTransport.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let agentCommandTransportLog = AppLog.make(category: "AgentCommandTransport")

// MARK: - AgentCommandTransport

struct AgentCommandTransport: Sendable {
  func encode(_ command: AgentCommand) throws -> Data {
    try JSONEncoder().encode(command)
  }

  func resume(
    _ resumer: AgentXPCReplyResumer,
    success: Bool,
    responseData: Data?,
    errorMessage: String?
  ) {
    if let errorMessage, !success {
      resumer.resume(
        throwing: FanCurveAgentClientError.commandRejected(errorMessage)
      )
      return
    }
    guard success, let responseData else {
      resumer.resume(throwing: FanCurveAgentClientError.invalidReply)
      return
    }
    resumer.resume(returning: responseData)
  }

  func decode(_ responseData: Data) throws -> AgentCommandResponse {
    do {
      return try JSONDecoder().decode(AgentCommandResponse.self, from: responseData)
    } catch {
      agentCommandTransportLog.error(
        "agent_command_transport.response_decode_failed error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-caller"
      )
      throw error
    }
  }

  func accept(
    _ response: AgentCommandResponse,
    for command: AgentCommand
  ) throws {
    guard response.accepted else {
      throw FanCurveAgentClientError.commandRejected(
        response.message ?? "Command rejected"
      )
    }
    agentCommandTransportLog.info(
      "agent_command_transport.command.sent kind=\(command.logName, privacy: .public)"
    )
  }
}
