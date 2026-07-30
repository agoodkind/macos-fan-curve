//
//  TickCoordinator.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

/// Serializes the agent's tick loop: at most one tick runs at a time, and at
/// most one more is queued behind it. Coordinating concurrency here is a
/// separate concern from liveness reporting; a tick that stays in flight for
/// a long time must not gate anything that answers "is the process alive"
/// (see `TickHeartbeatScheduler`).
actor TickCoordinator {
  private var tickInFlight = false
  private var tickPending = false

  func requestTick() -> Bool {
    if tickInFlight {
      tickPending = true
      return false
    }
    tickInFlight = true
    return true
  }

  func finishTick() -> Bool {
    if tickPending {
      tickPending = false
      return true
    }
    tickInFlight = false
    return false
  }
}
