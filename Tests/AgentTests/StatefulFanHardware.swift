//
//  StatefulFanHardware.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-04.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import XCTest

// MARK: - IdentityVerificationGate

actor IdentityVerificationGate {
  private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
  private var hasArrived = false
  private var suspendedRequest: CheckedContinuation<Void, Never>?

  func suspend() async {
    hasArrived = true
    let waiters = arrivalWaiters
    arrivalWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
    await withCheckedContinuation { continuation in
      suspendedRequest = continuation
    }
  }

  func waitForArrival() async {
    if hasArrived {
      return
    }
    await withCheckedContinuation { continuation in
      arrivalWaiters.append(continuation)
    }
  }

  func resume() {
    suspendedRequest?.resume()
    suspendedRequest = nil
  }
}

// MARK: - StatefulFanHardware

final class StatefulFanHardware: FanHardware, @unchecked Sendable {
  private static let firstAdditionalVerificationRequestCount = 3

  enum IdentityBehavior: Sendable {
    case connectionInvalidated
    case identity(SystemHelperIdentity)
    case legacy
    case unreachable
  }

  private static let legacyProbeDelaySeconds: Int64 = 5
  private static let legacyProbeDelay = Duration.seconds(
    legacyProbeDelaySeconds
  )
  private let lock = NSLock()
  private let identityDelay: Duration
  private let identityRequestStarted: XCTestExpectation?
  private let additionalVerificationStarted: XCTestExpectation?
  private let legacyProbeCancelled: XCTestExpectation?
  private let legacyProbeStarted: XCTestExpectation?
  private let resetBehavior: ReconcilerHarness.OperationBehavior
  private let verificationStarted: XCTestExpectation?
  private let verificationGate: IdentityVerificationGate?
  private var fanAutomatic = [false, false]
  private var identityBehavior: IdentityBehavior
  private var storedIdentityRequestCount = 0
  private var storedResetCount = 0
  private var verificationStartReported = false

  init(
    identity: IdentityBehavior,
    identityDelay: Duration,
    identityRequestStarted: XCTestExpectation?,
    additionalVerificationStarted: XCTestExpectation?,
    legacyProbeStarted: XCTestExpectation?,
    legacyProbeCancelled: XCTestExpectation?,
    verificationStarted: XCTestExpectation?,
    verificationGate: IdentityVerificationGate?,
    resetBehavior: ReconcilerHarness.OperationBehavior
  ) {
    self.identityBehavior = identity
    self.identityDelay = identityDelay
    self.identityRequestStarted = identityRequestStarted
    self.additionalVerificationStarted = additionalVerificationStarted
    self.legacyProbeStarted = legacyProbeStarted
    self.legacyProbeCancelled = legacyProbeCancelled
    self.verificationStarted = verificationStarted
    self.verificationGate = verificationGate
    self.resetBehavior = resetBehavior
  }

  var allFansAutomatic: Bool {
    lock.withLock { fanAutomatic.allSatisfy(\.self) }
  }
  var identityRequestCount: Int { lock.withLock { storedIdentityRequestCount } }
  var resetCount: Int { lock.withLock { storedResetCount } }

  func setIdentity(_ identity: IdentityBehavior) {
    lock.withLock { identityBehavior = identity }
  }

  func getHelperIdentity() async throws -> SystemHelperIdentity {
    let observation = lock.withLock {
      let shouldReportRequestStart = storedIdentityRequestCount == 0
      storedIdentityRequestCount += 1
      var shouldReportVerificationStart = false
      if storedIdentityRequestCount > 1,
        !verificationStartReported
      {
        verificationStartReported = true
        shouldReportVerificationStart = true
      }
      let shouldReportAdditionalVerification =
        storedIdentityRequestCount == Self.firstAdditionalVerificationRequestCount
      return (
        behavior: identityBehavior,
        shouldReportRequestStart: shouldReportRequestStart,
        shouldReportVerificationStart: shouldReportVerificationStart,
        shouldReportAdditionalVerification: shouldReportAdditionalVerification
      )
    }
    if observation.shouldReportRequestStart { identityRequestStarted?.fulfill() }
    if observation.shouldReportVerificationStart { verificationStarted?.fulfill() }
    if observation.shouldReportAdditionalVerification {
      additionalVerificationStarted?.fulfill()
    }
    if observation.shouldReportVerificationStart {
      await verificationGate?.suspend()
    }
    try await Task.sleep(for: identityDelay)
    switch observation.behavior {
    case .identity(let identity):
      return identity
    case .connectionInvalidated:
      // Mirrors SMCFanXPCClient reporting an invalidated helper connection
      // as CancellationError while the reconciliation task is not cancelled.
      throw CancellationError()
    case .legacy, .unreachable:
      throw TestFailure.unreachable
    }
  }

  func probeLegacyHelperReachability() async throws {
    let currentIdentity = lock.withLock { identityBehavior }
    switch currentIdentity {
    case .legacy:
      break
    case .connectionInvalidated:
      throw CancellationError()
    case .identity, .unreachable:
      throw TestFailure.unreachable
    }
    guard let legacyProbeStarted, let legacyProbeCancelled else {
      return
    }
    legacyProbeStarted.fulfill()
    do {
      try await Task.sleep(for: Self.legacyProbeDelay)
    } catch {
      legacyProbeCancelled.fulfill()
      throw error
    }
  }

  func resetAllDiscoveredFansToAuto() async throws {
    await Task.yield()
    lock.withLock { storedResetCount += 1 }
    if resetBehavior == .fail { throw TestFailure.reset }
    lock.withLock { fanAutomatic = fanAutomatic.map { _ in true } }
  }

  func shutdown() {
    // The in-memory test boundary has no connection to release.
  }

  func readAndApply(
    fanCount _: UInt,
    tempKeys _: [String],
    setFans _: [(index: UInt, rpm: Float)],
    autoFans _: [UInt],
    priority _: Int?
  ) async -> FanHardwareBatchRead {
    await Task.yield()
    return FanHardwareBatchRead(fans: [], temps: [:])
  }

  func enumerateKeys() async -> [String] {
    await Task.yield()
    return []
  }

  func getOwnership() async -> [AgentOwnershipEntry] {
    await Task.yield()
    return []
  }

  func setFanRPM(_: UInt, rpm _: Float, priority _: Int?) async {
    await Task.yield()
  }

  func setFanAuto(_: UInt, priority _: Int?) async {
    await Task.yield()
  }
}

// MARK: - StatefulHelperService

final class StatefulHelperService: HelperServiceManaging, @unchecked Sendable {
  private let lock = NSLock()
  private let mutationDelay: Duration
  private let registerBehavior: ReconcilerHarness.OperationBehavior
  private let unregisterCompleted: XCTestExpectation?
  private let unregisterFails: Bool
  private let unregisterStarted: XCTestExpectation?
  private var storedGeneration: Int
  private var storedRegisterAttemptCount = 0
  private var storedOnUnregistered: (@Sendable () throws -> Void)?
  private var storedUnregisterCount = 0
  private var storedOnRegistered: (@Sendable () -> Void)?
  private var storedStatus: ManagedServiceStatus

  init(
    status: ManagedServiceStatus,
    registrationGeneration: Int,
    unregisterFails: Bool,
    registerBehavior: ReconcilerHarness.OperationBehavior,
    unregisterStarted: XCTestExpectation?,
    unregisterCompleted: XCTestExpectation?,
    mutationDelay: Duration
  ) {
    storedStatus = status
    storedGeneration = registrationGeneration
    self.unregisterFails = unregisterFails
    self.registerBehavior = registerBehavior
    self.unregisterStarted = unregisterStarted
    self.unregisterCompleted = unregisterCompleted
    self.mutationDelay = mutationDelay
  }

  var status: ManagedServiceStatus { lock.withLock { storedStatus } }
  var registrationGeneration: Int { lock.withLock { storedGeneration } }
  var hasRegistration: Bool { status != .notRegistered }
  var unregisterCount: Int { lock.withLock { storedUnregisterCount } }

  func setOnRegistered(_ onRegistered: @escaping @Sendable () -> Void) {
    lock.withLock { storedOnRegistered = onRegistered }
  }

  func setOnUnregistered(
    _ onUnregistered: @escaping @Sendable () throws -> Void
  ) {
    lock.withLock { storedOnUnregistered = onUnregistered }
  }

  func unregister() async throws {
    unregisterStarted?.fulfill()
    try await Task.sleep(for: mutationDelay)
    if unregisterFails { throw TestFailure.unregister }
    let onUnregistered = lock.withLock {
      storedUnregisterCount += 1
      storedStatus = .notRegistered
      return storedOnUnregistered
    }
    try onUnregistered?()
    unregisterCompleted?.fulfill()
  }

  func register() async throws {
    try await Task.sleep(for: mutationDelay)
    let attempt = lock.withLock {
      storedRegisterAttemptCount += 1
      return storedRegisterAttemptCount
    }
    switch registerBehavior {
    case .fail:
      throw TestFailure.register
    case .operationNotPermitted:
      throw NSError(domain: "SMAppServiceErrorDomain", code: 1)
    case .operationNotPermittedOnce:
      if attempt == 1 {
        throw NSError(domain: "SMAppServiceErrorDomain", code: 1)
      }
      completeRegistration()
    case .requiresApproval:
      lock.withLock { storedStatus = .requiresApproval }
      throw TestFailure.register
    case .succeed:
      completeRegistration()
    }
  }

  private func completeRegistration() {
    let onRegistered = lock.withLock {
      storedGeneration += 1
      storedStatus = .enabled
      return storedOnRegistered
    }
    onRegistered?()
  }

  func openSystemSettings() {
    // The in-memory service has no settings application to open.
  }
}
