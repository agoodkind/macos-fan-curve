//
//  AgentXPCSessionTests.swift
//  FanCurveAgentTests
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-29.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

@MainActor
final class AgentXPCSessionTests: XCTestCase {
  /// An anonymous listener gives a real NSXPCConnection to own without
  /// standing up a service. The session only invalidates it.
  private func makeConnection() -> NSXPCConnection {
    let listener = NSXPCListener.anonymous()
    listener.resume()
    return NSXPCConnection(listenerEndpoint: listener.endpoint)
  }

  /// The invariant the whole design exists to guarantee: a request registered
  /// on a session that then ends is resumed, never abandoned. An abandoned
  /// continuation holds a task allocation and aborts the task allocator when
  /// its task unwinds.
  func testEndResumesRegisteredRequestRatherThanAbandoningIt() async throws {
    let session = AgentXPCSession(connection: makeConnection()) { _ in
      // This test only asserts request drainage.
    }
    let resumer = AgentXPCReplyResumer(operation: "current-state")
    let requestID = try XCTUnwrap(session.register(resumer))

    do {
      _ = try await withCheckedThrowingContinuation { continuation in
        resumer.install(continuation)
        session.end(.invalidated)
        session.release(requestID)
      }
      fail("Expected connectionUnavailable")
    } catch {
      if case FanCurveAgentClientError.connectionUnavailable = error {
        return
      }
      throw error
    }
  }

  func testEndBeforeContinuationInstallResumesWithConnectionUnavailable()
    async throws
  {
    let session = AgentXPCSession(connection: makeConnection()) { _ in
      // This test only asserts request drainage.
    }
    let resumer = AgentXPCReplyResumer(operation: "current-state")
    _ = try XCTUnwrap(session.register(resumer))

    session.end(.invalidated)

    let error = await operationErrorWithinTimeout {
      _ = try await withCheckedThrowingContinuation { continuation in
        resumer.install(continuation)
      }
    }

    guard let error else {
      fail("Expected connectionUnavailable")
      return
    }
    if case FanCurveAgentClientError.connectionUnavailable = error {
      return
    }
    throw error
  }

  func testClientStoppedResumesRegisteredRequestWithCancellationError()
    async throws
  {
    let session = AgentXPCSession(connection: makeConnection()) { _ in
      // This test only asserts request drainage.
    }
    let resumer = AgentXPCReplyResumer(operation: "current-state")
    let requestID = try XCTUnwrap(session.register(resumer))

    let error = await operationErrorWithinTimeout {
      _ = try await withCheckedThrowingContinuation { continuation in
        resumer.install(continuation)
        session.end(.clientStopped)
        session.release(requestID)
      }
    }

    guard let error else {
      fail("Expected CancellationError")
      return
    }
    expect(error is CancellationError) == true
  }

  func testEndIsIdempotentAndNotifiesItsOwnerOnce() {
    var endCount = 0
    let session = AgentXPCSession(connection: makeConnection()) { _ in
      endCount += 1
    }

    session.end(.interrupted)
    session.end(.invalidated)

    expect(endCount) == 1
    expect(session.hasEnded) == true
  }

  func testRegisterRefusesOnAnEndedSessionSoTheCallerFailsFast() {
    let session = AgentXPCSession(connection: makeConnection()) { _ in
      // This test only asserts registration refusal.
    }
    session.end(.clientStopped)

    let resumer = AgentXPCReplyResumer(operation: "current-state")

    expect(session.register(resumer)) == nil
    expect(session.pendingRequestCount) == 0
  }

  private func operationErrorWithinTimeout(
    operation: @escaping @MainActor () async throws -> Void
  ) async -> Error? {
    let completed = expectation(description: "XPC request completed")
    let operationTask = Task { @MainActor in
      try await operation()
    }
    var operationResult: Result<Void, Error>?
    let observationTask = Task { @MainActor in
      operationResult = await operationTask.result
      completed.fulfill()
    }

    await fulfillment(of: [completed], timeout: 1)
    operationTask.cancel()
    observationTask.cancel()
    guard let operationResult else {
      return nil
    }
    switch operationResult {
    case .success:
      return nil
    case .failure(let error):
      return error
    }
  }
}
