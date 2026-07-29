//
//  AgentXPCSession.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-29.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

let agentXPCSessionLog = AppLog.make(category: "AgentXPCSession")

// MARK: - AgentXPCSessionEndReason

/// Why a session ended, carrying the terminal error its in-flight requests
/// receive. A caller can tell a dropped connection from a deliberate stop.
enum AgentXPCSessionEndReason: Sendable {
  case clientStopped
  case interrupted
  case invalidated
  case proxyFailure(any Error)

  var terminalError: any Error {
    switch self {
    case .clientStopped:
      return CancellationError()
    case .interrupted, .invalidated:
      return FanCurveAgentClientError.connectionUnavailable
    case .proxyFailure(let error):
      return error
    }
  }

  /// Only a deliberate client stop suppresses reconnection.
  var allowsReconnect: Bool {
    switch self {
    case .clientStopped:
      return false
    case .interrupted, .invalidated, .proxyFailure:
      return true
    }
  }

  /// A stop cancels its requests, so `claimDispatch` can report a request that
  /// was cancelled before it ever dispatched. Every other reason is a failure.
  var cancelsRequests: Bool {
    switch self {
    case .clientStopped:
      return true
    case .interrupted, .invalidated, .proxyFailure:
      return false
    }
  }

  var logName: String {
    switch self {
    case .clientStopped:
      return "client-stopped"
    case .interrupted:
      return "interrupted"
    case .invalidated:
      return "invalidated"
    case .proxyFailure:
      return "proxy-failure"
    }
  }
}

// MARK: - AgentXPCSession

/// Owns one `NSXPCConnection` and every request in flight on it.
///
/// A request cannot outlive its connection. `end` is the single teardown path
/// and always resumes outstanding requests, so no continuation is abandoned.
/// An unresumed continuation holds a task allocation for the lifetime of its
/// task, which aborts the task allocator when that task unwinds.
@MainActor
final class AgentXPCSession {
  /// Identity for XPC handlers, which are `@Sendable` and cannot capture the
  /// session itself. A handler carries this value and the client compares it
  /// against its current session.
  let id = UUID()
  let connection: NSXPCConnection

  private var pendingRequests: [UUID: AgentXPCReplyResumer] = [:]
  private var endReason: AgentXPCSessionEndReason?
  private let onEnd: @MainActor (AgentXPCSessionEndReason) -> Void

  var hasEnded: Bool {
    endReason != nil
  }

  var pendingRequestCount: Int {
    pendingRequests.count
  }

  init(
    connection: NSXPCConnection,
    onEnd: @escaping @MainActor (AgentXPCSessionEndReason) -> Void
  ) {
    self.connection = connection
    self.onEnd = onEnd
    agentXPCSessionLog.notice(
      "agent_session.started session=\(self.id.uuidString, privacy: .public)"
    )
  }

  /// Registers a request against this session, or returns nil when the session
  /// has already ended so the caller fails fast rather than creating a
  /// continuation with no owner.
  func register(_ resumer: AgentXPCReplyResumer) -> UUID? {
    guard !hasEnded else {
      agentXPCSessionLog.notice(
        "agent_session.register_refused session=\(self.id.uuidString, privacy: .public) recovery=fail-request"
      )
      return nil
    }
    let requestID = UUID()
    pendingRequests[requestID] = resumer
    return requestID
  }

  func release(_ requestID: UUID) {
    pendingRequests.removeValue(forKey: requestID)
  }

  /// Ends the session exactly once: resumes every outstanding request, then
  /// invalidates the connection, then notifies its owner.
  func end(_ reason: AgentXPCSessionEndReason) {
    guard !hasEnded else {
      agentXPCSessionLog.debug(
        "agent_session.end_ignored session=\(self.id.uuidString, privacy: .public) reason=\(reason.logName, privacy: .public) recovery=already-ended"
      )
      return
    }
    endReason = reason

    // Remove each resumer before resuming it, so a re-entrant resume cannot
    // observe a stale entry. Resume before invalidating, so a resumed caller
    // never observes a half-torn-down session.
    let drained = pendingRequests
    pendingRequests.removeAll()
    for resumer in drained.values {
      if reason.cancelsRequests {
        resumer.cancel()
      } else {
        resumer.resume(throwing: reason.terminalError)
      }
    }

    let recovery: String
    if reason.allowsReconnect {
      recovery = "schedule-reconnect"
    } else {
      recovery = "stay-stopped"
    }
    agentXPCSessionLog.notice(
      "agent_session.ended session=\(self.id.uuidString, privacy: .public) reason=\(reason.logName, privacy: .public) drained=\(drained.count, privacy: .public) recovery=\(recovery, privacy: .public)"
    )

    connection.interruptionHandler = nil
    connection.invalidationHandler = nil
    connection.invalidate()

    onEnd(reason)
  }
}
