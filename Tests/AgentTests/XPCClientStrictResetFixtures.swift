//
//  XPCClientStrictResetFixtures.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import SMCFanProtocol
import XCTest

@testable import SMCFanXPCClient

enum XPCClientStrictResetFixtures {
  static let requestObservationTimeout: TimeInterval = 0.1
}

// MARK: - LifecycleRequestDispatchGate

actor LifecycleRequestDispatchGate {
  private var arrivalCount = 0
  private var arrivalWaiters:
    [(expectedCount: Int, continuation: CheckedContinuation<Void, Never>)] = []
  private var suspendedRequests: [CheckedContinuation<Void, Never>] = []

  func suspend() async {
    await withCheckedContinuation { continuation in
      suspendedRequests.append(continuation)
      arrivalCount += 1
      resumeSatisfiedArrivalWaiters()
    }
  }

  func waitForArrival(_ expectedCount: Int) async {
    if arrivalCount >= expectedCount {
      return
    }
    await withCheckedContinuation { continuation in
      arrivalWaiters.append((expectedCount, continuation))
    }
  }

  func resumeNext() {
    guard !suspendedRequests.isEmpty else { return }
    suspendedRequests.removeFirst().resume()
  }

  func resumeAll() {
    let requests = suspendedRequests
    suspendedRequests.removeAll()
    for request in requests {
      request.resume()
    }
  }

  private func resumeSatisfiedArrivalWaiters() {
    var remainingWaiters: [(expectedCount: Int, continuation: CheckedContinuation<Void, Never>)] =
      []
    for waiter in arrivalWaiters {
      if arrivalCount >= waiter.expectedCount {
        waiter.continuation.resume()
      } else {
        remainingWaiters.append(waiter)
      }
    }
    arrivalWaiters = remainingWaiters
  }
}

// MARK: - CountingXPCConnectionFactory

final class CountingXPCConnectionFactory: @unchecked Sendable {
  private let endpoint: NSXPCListenerEndpoint
  private let lock = NSLock()
  private var storedConnectionCount = 0

  var connectionCount: Int {
    lock.withLock { storedConnectionCount }
  }

  init(endpoint: NSXPCListenerEndpoint) {
    self.endpoint = endpoint
  }

  func makeConnection() -> NSXPCConnection {
    lock.withLock { storedConnectionCount += 1 }
    return NSXPCConnection(listenerEndpoint: endpoint)
  }
}

// MARK: - BoundedRequestObservation

private final class BoundedRequestObservation: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Bool, Never>?
  private var didFinish = false
  private var storedValue = false

  func record() {
    finish(with: true)
  }

  func value(timeout: TimeInterval) async -> Bool {
    await withCheckedContinuation { continuation in
      let existingResult = lock.withLock { () -> (didFinish: Bool, value: Bool) in
        if didFinish {
          return (true, storedValue)
        }
        self.continuation = continuation
        return (false, false)
      }
      if existingResult.didFinish {
        continuation.resume(returning: existingResult.value)
        return
      }
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
        self.finish(with: false)
      }
    }
  }

  private func finish(with value: Bool) {
    let pendingContinuation: CheckedContinuation<Bool, Never>? = lock.withLock {
      guard !didFinish else { return nil }
      didFinish = true
      storedValue = value
      let pendingContinuation = continuation
      continuation = nil
      return pendingContinuation
    }
    pendingContinuation?.resume(returning: value)
  }
}

// MARK: - ConflictingFanResetListenerDelegate

final class ConflictingFanResetListenerDelegate:
  NSObject,
  NSXPCListenerDelegate
{
  private let helper: ConflictingFanResetHelper

  init(helper: ConflictingFanResetHelper) {
    self.helper = helper
  }

  func listener(
    _: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    connection.exportedInterface = NSXPCInterface(
      with: SMCFanProtocol.SMCFanHelperProtocol.self
    )
    connection.exportedObject = helper
    connection.invalidationHandler = { [helper] in
      helper.recordConnectionInvalidation()
    }
    connection.resume()
    return true
  }
}

// MARK: - ConflictingFanResetHelper

final class ConflictingFanResetHelper:
  NSObject,
  SMCFanProtocol.SMCFanHelperProtocol,
  @unchecked Sendable
{
  private static let firstAdditionalRequestCount = 2

  enum FanCountReply {
    case fail(String)
    case succeed
    case withhold
  }

  enum FanAutoReply {
    case conflict
    case withhold
  }

  private let fanAutoReply: FanAutoReply
  private let fanCountRequestObservation = BoundedRequestObservation()
  private let fanAutoRequests: AsyncStream<Void>
  private let fanAutoRequestContinuation: AsyncStream<Void>.Continuation
  private var fanCountReply: FanCountReply
  private let connectionInvalidated: XCTestExpectation?
  private let additionalFanAutoRequest: XCTestExpectation?
  private let additionalFanCountRequest: XCTestExpectation?
  private let fanCountRequests: AsyncStream<Void>
  private let fanCountRequestContinuation: AsyncStream<Void>.Continuation
  private let lock = NSLock()
  private var storedAutoResetCallCount = 0
  private var storedFanCountCallCount = 0

  var autoResetCallCount: Int { lock.withLock { storedAutoResetCallCount } }
  var fanCountCallCount: Int { lock.withLock { storedFanCountCallCount } }

  init(
    fanCountReply: FanCountReply = .succeed,
    fanAutoReply: FanAutoReply = .conflict,
    connectionInvalidated: XCTestExpectation? = nil,
    additionalFanCountRequest: XCTestExpectation? = nil,
    additionalFanAutoRequest: XCTestExpectation? = nil
  ) {
    let (requests, continuation) = AsyncStream.makeStream(of: Void.self)
    let (autoRequests, autoContinuation) = AsyncStream.makeStream(of: Void.self)
    self.fanCountRequests = requests
    self.fanCountRequestContinuation = continuation
    self.fanAutoRequests = autoRequests
    self.fanAutoRequestContinuation = autoContinuation
    self.fanCountReply = fanCountReply
    self.fanAutoReply = fanAutoReply
    self.connectionInvalidated = connectionInvalidated
    self.additionalFanCountRequest = additionalFanCountRequest
    self.additionalFanAutoRequest = additionalFanAutoRequest
  }

  func waitForFanCountRequest() async {
    for await _ in fanCountRequests {
      return
    }
  }

  func fanCountRequestObserved(timeout: TimeInterval) async -> Bool {
    await fanCountRequestObservation.value(timeout: timeout)
  }

  func waitForFanAutoRequest() async {
    for await _ in fanAutoRequests {
      return
    }
  }

  func setFanCountReply(_ reply: FanCountReply) {
    lock.withLock { fanCountReply = reply }
  }

  func recordConnectionInvalidation() {
    connectionInvalidated?.fulfill()
  }

  func smcGetIdentity(reply: SMCFanProtocol.SMCFanHelperIdentityReply) {
    reply(false, "", "", "", "", 0, "Not implemented")
  }

  func smcOpen(reply: (Bool, String?) -> Void) { reply(true, nil) }
  func smcClose(reply: (Bool, String?) -> Void) { reply(true, nil) }

  func smcReadKey(
    _: String,
    reply: (Bool, Float, String?) -> Void
  ) {
    reply(false, 0, "Not implemented")
  }

  func smcReadKeys(
    _ keys: [String],
    reply: ([Bool], [Float], [String]) -> Void
  ) {
    reply(
      Array(repeating: false, count: keys.count),
      Array(repeating: 0, count: keys.count),
      Array(repeating: "Not implemented", count: keys.count)
    )
  }

  func smcWriteKey(
    _: String,
    value _: Float,
    reply: (Bool, String?) -> Void
  ) {
    reply(false, "Not implemented")
  }

  func smcGetFanCount(
    reply: @Sendable (Bool, UInt, String?) -> Void
  ) {
    let requestCount = lock.withLock {
      storedFanCountCallCount += 1
      return storedFanCountCallCount
    }
    if requestCount == Self.firstAdditionalRequestCount {
      additionalFanCountRequest?.fulfill()
    }
    fanCountRequestObservation.record()
    fanCountRequestContinuation.yield()
    let selectedReply = lock.withLock { fanCountReply }
    switch selectedReply {
    case .fail(let message):
      reply(false, 0, message)
    case .succeed:
      reply(true, 1, nil)
    case .withhold:
      break
    }
  }

  func smcGetFanInfo(
    _: UInt,
    reply: (Bool, Float, Float, Float, Float, Bool, String?) -> Void
  ) {
    reply(false, 0, 0, 0, 0, false, "Not implemented")
  }

  func smcSetFanRPM(
    _: UInt,
    rpm _: Float,
    priority _: Int,
    reply: (Bool, Bool, String?) -> Void
  ) {
    reply(false, false, "Not implemented")
  }

  func smcSetFanAuto(
    _: UInt,
    priority _: Int,
    reply: (Bool, Bool, String?) -> Void
  ) {
    let requestCount = lock.withLock {
      storedAutoResetCallCount += 1
      return storedAutoResetCallCount
    }
    if requestCount == Self.firstAdditionalRequestCount {
      additionalFanAutoRequest?.fulfill()
    }
    fanAutoRequestContinuation.yield()
    switch fanAutoReply {
    case .conflict:
      reply(false, true, "Preempted by test owner")
    case .withhold:
      break
    }
  }

  func smcEnumerateKeys(reply: ([String]) -> Void) { reply([]) }

  func smcRegisterClient(
    name _: String,
    reply: (Bool, String?) -> Void
  ) {
    reply(true, nil)
  }

  func smcGetOwnership(
    reply: ([UInt], [String], [Int], [Double]) -> Void
  ) {
    reply([], [], [], [])
  }
}
