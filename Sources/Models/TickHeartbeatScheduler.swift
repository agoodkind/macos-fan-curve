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
///
/// `start()` runs on whichever thread the agent starts on, while `stop()` is
/// reached from the signal handler's `Task`, which is not main-actor
/// isolated. A `Timer` belongs to the run loop that scheduled it, so both
/// calls are funnelled onto the main thread and `timer` is guarded, keeping
/// scheduling and invalidation on one executor.
final class TickHeartbeatScheduler: @unchecked Sendable {
  private let lock = NSLock()
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
    onMainThread { [self] in
      let scheduled = Timer.scheduledTimer(
        withTimeInterval: interval,
        repeats: true
      ) { [weak self] _ in
        self?.publish()
      }
      lock.lock()
      timer = scheduled
      lock.unlock()
    }
  }

  func stop() {
    lock.lock()
    let scheduled = timer
    timer = nil
    lock.unlock()
    guard let scheduled else { return }
    onMainThread { scheduled.invalidate() }
  }

  /// Runs `body` on the main thread, synchronously when already there. The
  /// synchronous path matters for a caller that schedules and then drives
  /// the run loop itself, which would otherwise never see the timer.
  ///
  /// `body` is not `@Sendable` because `Timer` is not `Sendable`. Confining
  /// every use to the main thread is what makes the capture safe, which is
  /// the same guarantee this type exists to provide.
  private func onMainThread(_ body: @escaping () -> Void) {
    if Thread.isMainThread {
      body()
    } else {
      let box = UncheckedBox(body)
      DispatchQueue.main.async { box.value() }
    }
  }
}

// MARK: - UncheckedBox

/// Carries a main-thread-only closure across a `DispatchQueue.main.async`
/// boundary. The closure captures a `Timer`, which is not `Sendable`, and is
/// only ever invoked on the main thread.
private struct UncheckedBox: @unchecked Sendable {
  let value: () -> Void

  init(_ value: @escaping () -> Void) {
    self.value = value
  }
}
