//
//  AgentXPCRequest.swift
//  FanCurve
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

// MARK: - AgentXPCRequest

enum AgentXPCRequest: Sendable {
  case command(Data, name: String)
  case currentState
  case ownership
  case registerEvents

  var operation: String {
    switch self {
    case .command(_, let name):
      return "command-\(name)"
    case .currentState:
      return "current-state"
    case .ownership:
      return "ownership"
    case .registerEvents:
      return "register-events"
    }
  }
}

// MARK: - FanCurveAgentConnectionState

enum FanCurveAgentConnectionState: Sendable, Equatable {
  case connected
  case connecting
  case disconnected
  case failed(String)
}

// MARK: - FanCurveAgentClientError

enum FanCurveAgentClientError: LocalizedError {
  case commandRejected(String)
  case connectionUnavailable
  case invalidReply
  case missingRemoteProxy

  var errorDescription: String? {
    switch self {
    case .commandRejected(let message):
      return message
    case .connectionUnavailable:
      return "FanCurveAgent XPC connection is unavailable"
    case .invalidReply:
      return "FanCurveAgent returned an invalid reply"
    case .missingRemoteProxy:
      return "FanCurveAgent remote proxy is unavailable"
    }
  }
}

// MARK: - AgentXPCReplyResumer

final class AgentXPCReplyResumer: @unchecked Sendable {
  private let lock = NSLock()
  private let operation: String
  private var continuation: CheckedContinuation<Data?, Error>?
  private var pendingResult: Result<Data?, Error>?
  private var isCompleted = false

  init(operation: String) {
    self.operation = operation
  }

  func install(_ continuation: CheckedContinuation<Data?, Error>) {
    lock.lock()
    let result = pendingResult
    if result != nil {
      pendingResult = nil
    } else {
      self.continuation = continuation
    }
    lock.unlock()
    resume(continuation, with: result)
  }

  func resume(returning value: Data? = nil) {
    complete(.success(value))
  }

  func resume(throwing error: Error) {
    complete(.failure(error))
  }

  func cancel() {
    fanCurveAgentClientLog.notice(
      "agent_client.request.cancelled operation=\(operation, privacy: .public) recovery=resume-continuation"
    )
    resume(throwing: CancellationError())
  }

  private func complete(_ result: Result<Data?, Error>) {
    lock.lock()
    if isCompleted {
      lock.unlock()
      return
    }
    isCompleted = true
    guard let continuation else {
      pendingResult = result
      lock.unlock()
      return
    }
    self.continuation = nil
    lock.unlock()
    resume(continuation, with: result)
  }

  private func resume(
    _ continuation: CheckedContinuation<Data?, Error>?,
    with result: Result<Data?, Error>?
  ) {
    guard let continuation, let result else {
      return
    }
    continuation.resume(with: result)
  }

  func resume(success: Bool, errorMessage: String?) {
    if success {
      resume()
      return
    }
    resume(
      throwing: FanCurveAgentClientError.commandRejected(
        errorMessage ?? "Command rejected"
      )
    )
  }
}
