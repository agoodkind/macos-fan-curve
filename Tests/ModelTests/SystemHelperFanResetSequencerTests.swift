//
//  SystemHelperFanResetSequencerTests.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-04.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import OSLog
import XCTest

@testable import FanCurveModels

final class SystemHelperFanResetSequencerTests: XCTestCase {
  func testCompletedResetReturnsCompleted() async {
    let outcome = await SystemHelperFanResetSequencer.resetWithinDeadline(
      deadline: 0.2
    ) {
      // A successful reset performs no extra work in this boundary test.
    }

    expect(outcome) == .completed
  }

  func testResetFailurePreservesItsReason() async {
    let outcome = await SystemHelperFanResetSequencer.resetWithinDeadline(
      deadline: 0.2
    ) {
      throw ResetFailure.refused
    }

    expect(outcome) == .failed(reason: "refused")
  }

  func testUnresponsiveResetReturnsTimedOut() async {
    let outcome = await SystemHelperFanResetSequencer.resetWithinDeadline(
      deadline: 0.02
    ) {
      try await Task.sleep(for: .seconds(1))
    }

    expect(outcome) == .timedOut
  }

  func testTimeoutCancelsResetAndWritesOneTerminalLog() async throws {
    let deadline: TimeInterval = 0.031337
    let logStore = try OSLogStore(scope: .currentProcessIdentifier)
    let logPosition = logStore.position(date: Date())
    let resetStarted = expectation(description: "reset started")
    let resetCancelled = expectation(description: "reset cancelled")
    let releaseReset = AsyncTestGate()
    let resetTask = Task {
      await SystemHelperFanResetSequencer.resetWithinDeadline(deadline: deadline) {
        resetStarted.fulfill()
        await withTaskCancellationHandler {
          await releaseReset.wait()
        } onCancel: {
          resetCancelled.fulfill()
        }
      }
    }
    await fulfillment(of: [resetStarted], timeout: 1)

    let outcome = await resetTask.value
    await fulfillment(of: [resetCancelled], timeout: 1)
    await releaseReset.open()
    await Task.yield()

    var resetMessages: [String] = []
    for entry in try logStore.getEntries(at: logPosition) {
      guard let logEntry = entry as? OSLogEntryLog else { continue }
      if logEntry.composedMessage.contains("system_helper.reset.") {
        resetMessages.append(logEntry.composedMessage)
      }
    }
    let startMarker = "system_helper.reset.started deadlineSeconds=\(deadline)"
    let startIndex = try XCTUnwrap(
      resetMessages.lastIndex { $0.contains(startMarker) }
    )
    let terminalMessages = resetMessages[resetMessages.index(after: startIndex)...]
      .filter { $0.contains("system_helper.reset.finished") }
    expect(outcome) == .timedOut
    expect(terminalMessages).to(haveCount(1))
    expect(terminalMessages.first).to(contain("outcome=timed_out"))
  }
}

// MARK: - AsyncTestGate

private actor AsyncTestGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func open() {
    isOpen = true
    let pendingWaiters = waiters
    waiters.removeAll()
    for waiter in pendingWaiters {
      waiter.resume()
    }
  }
}

// MARK: - ResetFailure

private enum ResetFailure: LocalizedError {
  case refused

  var errorDescription: String? { "refused" }
}
