//
//  TickHeartbeatScheduler.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import Foundation

/// Publishes a cheap liveness heartbeat on its own timer cadence, entirely
/// independent of `TickCoordinator` and however long the tick's own async
/// work takes. A tick can stall for a long time waiting on a slow XPC call;
/// the heartbeat must keep advancing regardless, since it answers "is this
/// process alive" rather than "how fresh is the tick's data" (that question
/// belongs to `AgentSnapshot.timestamp`).
final class TickHeartbeatScheduler: @unchecked Sendable {
  private var timer: Timer?
  private let interval: TimeInterval
  private let publish: () -> Void

  init(interval: TimeInterval, publish: @escaping () -> Void) {
    self.interval = interval
    self.publish = publish
  }

  /// Publishes once immediately, then again every `interval` until `stop()`.
  func start() {
    stop()
    publish()
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      self?.publish()
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }
}
