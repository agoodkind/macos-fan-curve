//
//  TickHeartbeatScheduler.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

let tickHeartbeatLog = AppLog.make(category: "TickHeartbeatScheduler")

// MARK: - TickHeartbeatScheduler

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
/// calls funnel their timer work onto the main thread.
///
/// Invalidation from off the main thread is necessarily queued, so a timer
/// can still fire between `stop()` returning and that queued invalidation
/// running. Every scheduled timer therefore carries the generation it was
/// created in, and a fire whose generation is stale publishes nothing. That
/// is what stops a late heartbeat writing status after
/// `AgentController.stop()` has already cleared it.
final class TickHeartbeatScheduler: @unchecked Sendable {
  private let lock = NSLock()
  private var timer: Timer?
  private var generation: UInt64 = 0
  private var running = false
  private let interval: TimeInterval
  private let publish: () -> Void

  init(interval: TimeInterval, publish: @escaping () -> Void) {
    self.interval = interval
    self.publish = publish
  }

  /// Publishes once immediately, then again every `interval` until `stop()`.
  func start() {
    stop()

    lock.lock()
    generation &+= 1
    let thisGeneration = generation
    running = true
    lock.unlock()

    tickHeartbeatLog.notice(
      "heartbeat.started intervalSeconds=\(interval, privacy: .public) generation=\(thisGeneration, privacy: .public)"
    )
    publish()

    onMainThread { [self] in
      let scheduled = Timer.scheduledTimer(
        withTimeInterval: interval,
        repeats: true
      ) { [weak self] _ in
        self?.publishIfCurrent(thisGeneration)
      }
      lock.lock()
      // A stop() that landed while this was queued already moved the
      // generation on, so drop the timer rather than installing it.
      if generation == thisGeneration {
        timer = scheduled
      } else {
        scheduled.invalidate()
      }
      lock.unlock()
    }
  }

  func stop() {
    lock.lock()
    let wasRunning = running
    running = false
    generation &+= 1
    let scheduled = timer
    timer = nil
    lock.unlock()

    if wasRunning {
      tickHeartbeatLog.notice("heartbeat.stopped")
    }
    guard let scheduled else { return }
    onMainThread { scheduled.invalidate() }
  }

  /// Publishes only when this fire belongs to the current run. A timer whose
  /// invalidation is still queued can fire once more after `stop()`; that
  /// fire must not write liveness for a scheduler that is already stopped.
  private func publishIfCurrent(_ firedGeneration: UInt64) {
    lock.lock()
    let isCurrent = running && generation == firedGeneration
    lock.unlock()
    guard isCurrent else { return }
    publish()
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
