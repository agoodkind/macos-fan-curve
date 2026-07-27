//
//  AgentCommandTransport.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let agentCommandTransportLog = AppLog.make(category: "AgentCommandTransport")

// MARK: - AgentCommandReplyResumer

private final class AgentCommandReplyResumer: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<AgentCommandResponse, Error>?

  init(_ continuation: CheckedContinuation<AgentCommandResponse, Error>) {
    self.continuation = continuation
  }

  func resume(success: Bool, responseData: Data?, errorMessage: String?) {
    if let errorMessage, !success {
      resume(throwing: FanCurveAgentClientError.commandRejected(errorMessage))
      return
    }
    guard success, let responseData else {
      resume(throwing: FanCurveAgentClientError.invalidReply)
      return
    }
    do {
      let response = try JSONDecoder().decode(AgentCommandResponse.self, from: responseData)
      resume(returning: response)
    } catch {
      agentCommandTransportLog.error(
        "agent_command_transport.response_decode_failed error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-caller"
      )
      resume(throwing: error)
    }
  }

  func resume(returning response: AgentCommandResponse) {
    lock.lock()
    defer { lock.unlock() }
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(returning: response)
  }

  func resume(throwing error: Error) {
    lock.lock()
    defer { lock.unlock() }
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(throwing: error)
  }
}

// MARK: - AgentCommandTransport

@MainActor
final class AgentCommandTransport {
  private let encoder = JSONEncoder()
  private let serviceName: String

  init(serviceName: String) {
    self.serviceName = serviceName
  }

  func sendControl(_ command: AgentCommand) async throws {
    agentCommandTransportLog.notice(
      "agent_command_transport.control.started kind=\(command.logName, privacy: .public) transport=one-shot-xpc"
    )
    let connection = NSXPCConnection(machServiceName: serviceName, options: [])
    connection.remoteObjectInterface = NSXPCInterface(with: FanCurveAgentXPCProtocol.self)
    connection.resume()
    defer {
      connection.invalidate()
    }

    do {
      let data = try encoder.encode(command)
      let response: AgentCommandResponse =
        try await withCheckedThrowingContinuation { continuation in
          let resumer = AgentCommandReplyResumer(continuation)
          let errorHandler: @Sendable (Error) -> Void = { error in
            agentCommandTransportLog.error(
              "agent_command_transport.control_proxy.failed kind=\(command.logName, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-command"
            )
            resumer.resume(throwing: error)
          }
          guard
            let proxy = connection.remoteObjectProxyWithErrorHandler(errorHandler)
              as? FanCurveAgentXPCProtocol
          else {
            resumer.resume(throwing: FanCurveAgentClientError.missingRemoteProxy)
            return
          }
          request(commandData: data, using: proxy, resumer: resumer)
        }
      try accept(response, for: command)
      agentCommandTransportLog.notice(
        "agent_command_transport.control.finished kind=\(command.logName, privacy: .public) transport=one-shot-xpc"
      )
    } catch {
      agentCommandTransportLog.error(
        "agent_command_transport.control.failed kind=\(command.logName, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-ui"
      )
      throw error
    }
  }

  func send(
    _ command: AgentCommand,
    to proxy: FanCurveAgentXPCProtocol
  ) async throws {
    let data = try encoder.encode(command)
    let response: AgentCommandResponse =
      try await withCheckedThrowingContinuation { continuation in
        let resumer = AgentCommandReplyResumer(continuation)
        request(commandData: data, using: proxy, resumer: resumer)
      }
    try accept(response, for: command)
  }

  private func request(
    commandData: Data,
    using proxy: FanCurveAgentXPCProtocol,
    resumer: AgentCommandReplyResumer
  ) {
    proxy.sendCommand(commandData) { success, responseData, errorMessage in
      resumer.resume(
        success: success,
        responseData: responseData,
        errorMessage: errorMessage
      )
    }
  }

  private func accept(
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
