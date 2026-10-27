//
//  AgentControllerTickIdleTests.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-10-27.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

private enum AgentControllerTickIdleTestValues {
  static let label = "AgentControllerTickIdleTests"
  static let staleError = "stale tick error"
  static let heldTickObservationMilliseconds = 200
  static let heldTickObservation: Duration = .milliseconds(heldTickObservationMilliseconds)
}

// MARK: - AgentControllerTickIdleTests

@MainActor
final class AgentControllerTickIdleTests: XCTestCase {
  func testWaitUntilTickIdleReturnsAfterPausedTickWritesSharedConfig() async throws {
    let scratch = try ScratchDefaults(label: AgentControllerTickIdleTestValues.label)
    defer { scratch.remove() }
    let defaults = scratch.defaults
    defaults.set(
      AgentControllerTickIdleTestValues.staleError,
      forKey: SharedConfigKeys.agentLastError
    )
    let hardware = GatedReadFanHardware()
    let controller = AgentController(
      fanHardware: hardware,
      sharedConfig: SharedConfig(defaults: defaults)
    )

    controller.resume()
    await hardware.waitUntilReadStarts()
    controller.pause()
    let waitReturned = TestControlBooleanObservation()
    let waiter = Task { @MainActor in
      await controller.waitUntilTickIdle()
      waitReturned.record()
    }
    try await Task.sleep(for: AgentControllerTickIdleTestValues.heldTickObservation)

    expect(waitReturned.value) == false
    expect(defaults.string(forKey: SharedConfigKeys.agentLastError))
      == AgentControllerTickIdleTestValues.staleError

    hardware.releaseRead()
    await waiter.value

    expect(waitReturned.value) == true
    expect(defaults.string(forKey: SharedConfigKeys.agentLastError)) == nil
  }
}

// MARK: - GatedReadFanHardware

private final class GatedReadFanHardware: FanHardware, @unchecked Sendable {
  private let lock = NSLock()
  private var readStarted = false
  private var readReleased = false
  private var readStartWaiters: [CheckedContinuation<Void, Never>] = []
  private var heldRead: CheckedContinuation<Void, Never>?

  func waitUntilReadStarts() async {
    await withCheckedContinuation { continuation in
      let started = lock.withLock {
        if readStarted {
          return true
        }
        readStartWaiters.append(continuation)
        return false
      }
      if started {
        continuation.resume()
      }
    }
  }

  func releaseRead() {
    let held = lock.withLock {
      readReleased = true
      let continuation = heldRead
      heldRead = nil
      return continuation
    }
    held?.resume()
  }

  func shutdown() {
    // The test double has no external connection to close.
  }

  func enumerateKeys() async -> [String] {
    await Task.yield()
    return []
  }

  func readAndApply(
    fanCount _: UInt,
    tempKeys _: [String],
    setFans _: [(index: UInt, rpm: Float)],
    autoFans _: [UInt],
    priority _: Int?
  ) async -> FanHardwareBatchRead {
    let waiters = lock.withLock {
      readStarted = true
      let pending = readStartWaiters
      readStartWaiters = []
      return pending
    }
    for waiter in waiters {
      waiter.resume()
    }
    await withCheckedContinuation { continuation in
      let released = lock.withLock {
        if readReleased {
          return true
        }
        heldRead = continuation
        return false
      }
      if released {
        continuation.resume()
      }
    }
    return FanHardwareBatchRead(fans: [], temps: [:])
  }

  func getOwnership() async throws -> [AgentOwnershipEntry] {
    await Task.yield()
    try Task.checkCancellation()
    return []
  }

  func setFanRPM(_: UInt, rpm _: Float, priority _: Int?) async throws {
    await Task.yield()
    try Task.checkCancellation()
  }

  func setFanAuto(_: UInt, priority _: Int?) async throws {
    await Task.yield()
    try Task.checkCancellation()
  }
}
