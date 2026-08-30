//
//  TickHeartbeatSchedulerTests.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class TickHeartbeatSchedulerTests: XCTestCase {
  /// A stalled tick must not freeze liveness. This drives a real `Timer` on
  /// the run loop while a `TickCoordinator` tick is left in flight for the
  /// whole test (never finished), and asserts the heartbeat still advances
  /// repeatedly during that window.
  func testHeartbeatAdvancesWhileTickStaysInFlight() {
    var heartbeatCount = 0
    let scheduler = TickHeartbeatScheduler(interval: 0.05) {
      heartbeatCount += 1
    }

    let tickCoordinator = TickCoordinator()
    let tickStarted = expectation(description: "tick requested")
    Task {
      let started = await tickCoordinator.requestTick()
      expect(started) == true
      tickStarted.fulfill()
    }
    wait(for: [tickStarted], timeout: 1.0)

    scheduler.start()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    scheduler.stop()

    // The simulated tick is still in flight here: `finishTick()` was never
    // called. The heartbeat firing several times anyway is exactly the
    // independence the fix relies on.
    expect(heartbeatCount) >= 3
  }

  func testStopPreventsFurtherHeartbeats() {
    var heartbeatCount = 0
    let scheduler = TickHeartbeatScheduler(interval: 0.05) {
      heartbeatCount += 1
    }

    scheduler.start()
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    scheduler.stop()
    let countAfterStop = heartbeatCount

    RunLoop.current.run(until: Date().addingTimeInterval(0.15))

    expect(heartbeatCount) == countAfterStop
  }
}
