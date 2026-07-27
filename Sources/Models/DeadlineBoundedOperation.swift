//
//  DeadlineBoundedOperation.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - DeadlineOutcome

/// Outcome of racing an async operation against a fixed wall-clock deadline.
enum DeadlineOutcome: Equatable {
  case completed
  case deadlineExceeded
}

// MARK: - SingleResumeGuard

/// Ensures a `CheckedContinuation` is resumed exactly once when two
/// unstructured tasks race to finish first.
private final class SingleResumeGuard: @unchecked Sendable {
  private let lock = NSLock()
  private var hasResumed = false

  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !hasResumed else { return false }
    hasResumed = true
    return true
  }
}

// MARK: - DeadlineBoundedOperation

/// Races an async operation against a hard deadline and returns as soon as
/// either resolves, without waiting for the loser. The operation runs as an
/// unstructured task rather than a `TaskGroup` child specifically so a
/// non-cancellable operation (an in-flight XPC call, for example, cannot be
/// interrupted mid-round-trip) never blocks the return past the deadline:
/// structured concurrency would otherwise implicitly await every child task
/// before `withTaskGroup` returns, defeating the deadline entirely. The
/// deadline timer uses `DispatchQueue.asyncAfter` rather than `Task.sleep`,
/// which keeps this a plain scheduled callback instead of a blocking wait.
/// Used where the caller has its own fixed budget (for example launchd's
/// SIGTERM-to-SIGKILL grace period) and returning late is worse than the
/// operation finishing incomplete.
enum DeadlineBoundedOperation {
  static func run(
    deadline: TimeInterval,
    operation: @escaping @Sendable () async -> Void
  ) async -> DeadlineOutcome {
    await withCheckedContinuation { (continuation: CheckedContinuation<DeadlineOutcome, Never>) in
      let resumeGuard = SingleResumeGuard()

      Task {
        await operation()
        if resumeGuard.claim() {
          continuation.resume(returning: .completed)
        }
      }

      DispatchQueue.global().asyncAfter(deadline: .now() + deadline) {
        if resumeGuard.claim() {
          continuation.resume(returning: .deadlineExceeded)
        }
      }
    }
  }
}
