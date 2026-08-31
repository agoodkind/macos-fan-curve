//
//  DeadlineBoundedOperationTests.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class DeadlineBoundedOperationTests: XCTestCase {
  func testOperationFinishingBeforeDeadlineReturnsCompleted() async {
    let outcome = await DeadlineBoundedOperation.run(deadline: 0.5) {
      do {
        try await Task.sleep(nanoseconds: 10_000_000)
      } catch {
        return  // ignore cancellation, treat as a no-op
      }
    }

    expect(outcome) == .completed
  }

  func testOperationExceedingDeadlineReturnsPromptly() async {
    let start = Date()

    let outcome = await DeadlineBoundedOperation.run(deadline: 0.1) {
      do {
        try await Task.sleep(nanoseconds: 2_000_000_000)
      } catch {
        return  // ignore cancellation, treat as a no-op
      }
    }

    let elapsed = Date().timeIntervalSince(start)

    expect(outcome) == .deadlineExceeded
    // Proves the call returns near the 0.1s deadline instead of waiting out
    // the full 2s operation.
    expect(elapsed) < 1.0
  }
}
