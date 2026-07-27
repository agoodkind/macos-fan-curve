//
//  AgentShutdownSequencerTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

/// Records event order under a lock so the test can assert real execution
/// order across the actual async race, not just the code's apparent order.
private final class OrderRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var events: [String] = []

  func record(_ event: String) {
    lock.lock()
    defer { lock.unlock() }
    events.append(event)
  }
}

// MARK: - AgentShutdownSequencerTests

final class AgentShutdownSequencerTests: XCTestCase {
  func testStopsTickingBeforeResetAndCompletesWithinDeadline() async {
    let recorder = OrderRecorder()

    let outcome = await AgentShutdownSequencer.resetWithinDeadline(
      deadline: 0.5,
      stopTicking: { recorder.record("stopped-ticking") },
      resetFans: {
        recorder.record("reset-started")
        do {
          try await Task.sleep(nanoseconds: 20_000_000)
        } catch {
          return  // ignore cancellation, treat as a no-op
        }
        recorder.record("reset-finished")
      }
    )

    expect(outcome) == .completed
    expect(recorder.events) == ["stopped-ticking", "reset-started", "reset-finished"]
  }

  func testStopsTickingBeforeResetAndReturnsPromptlyOnDeadline() async {
    let recorder = OrderRecorder()
    let start = Date()

    let outcome = await AgentShutdownSequencer.resetWithinDeadline(
      deadline: 0.1,
      stopTicking: { recorder.record("stopped-ticking") },
      resetFans: {
        recorder.record("reset-started")
        do {
          try await Task.sleep(nanoseconds: 2_000_000_000)
        } catch {
          return  // ignore cancellation, treat as a no-op
        }
        recorder.record("reset-finished")
      }
    )

    let elapsed = Date().timeIntervalSince(start)

    expect(outcome) == .deadlineExceeded
    expect(recorder.events.first) == "stopped-ticking"
    expect(recorder.events).notTo(contain("reset-finished"))
    expect(elapsed) < 1.0
  }
}
