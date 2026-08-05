//
//  SystemHelperFanResetSequencer.swift
//  FanCurveAgent
//
//  Created by Codex <noreply@openai.com> on 2026-08-04.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let log = AppLog.make(
  category: "SystemHelperFanResetSequencer"
)

// MARK: - SystemHelperFanResetOutcome

enum SystemHelperFanResetOutcome: Equatable, Sendable {
  case cancelled
  case completed
  case failed(reason: String)
  case timedOut
}

// MARK: - SystemHelperFanResetResolution

private struct SystemHelperFanResetResolution {
  let continuation: CheckedContinuation<SystemHelperFanResetOutcome, Never>?
  let deadlineTask: Task<Void, Never>?
  let resetTask: Task<Void, Never>?
}

// MARK: - SystemHelperFanResetCompletion

private final class SystemHelperFanResetCompletion: @unchecked Sendable {
  private enum Finisher: Equatable {
    case cancellation
    case deadline
    case reset
  }

  private let lock = NSLock()
  private var continuation: CheckedContinuation<SystemHelperFanResetOutcome, Never>?
  private var deadlineTask: Task<Void, Never>?
  private var outcome: SystemHelperFanResetOutcome?
  private var resetTask: Task<Void, Never>?

  func install(
    _ continuation: CheckedContinuation<SystemHelperFanResetOutcome, Never>
  ) {
    let resolvedOutcome = lock.withLock { () -> SystemHelperFanResetOutcome? in
      if let storedOutcome = outcome { return storedOutcome }
      self.continuation = continuation
      return nil
    }
    if let resolvedOutcome {
      continuation.resume(returning: resolvedOutcome)
    }
  }

  func installTasks(
    resetTask: Task<Void, Never>,
    deadlineTask: Task<Void, Never>
  ) {
    let shouldCancel = lock.withLock {
      guard outcome == nil else { return true }
      self.resetTask = resetTask
      self.deadlineTask = deadlineTask
      return false
    }
    if shouldCancel {
      resetTask.cancel()
      deadlineTask.cancel()
    }
  }

  func cancel() {
    finish(.cancelled, finisher: .cancellation) {
      log.notice(
        "system_helper.reset.finished outcome=cancelled recovery=preserve-registration"
      )
    }
  }

  func finishReset(_ resolvedOutcome: SystemHelperFanResetOutcome) {
    finish(resolvedOutcome, finisher: .reset) {
      switch resolvedOutcome {
      case .completed:
        log.notice(
          "system_helper.reset.finished outcome=completed"
        )
      case .failed(let reason):
        log.error(
          "system_helper.reset.finished outcome=failed reason=\(reason, privacy: .public) recovery=preserve-registration"
        )
      case .cancelled, .timedOut:
        break
      }
    }
  }

  func finishDeadline(deadline: TimeInterval) {
    finish(.timedOut, finisher: .deadline) {
      log.error(
        "system_helper.reset.finished outcome=timed_out deadlineSeconds=\(deadline, privacy: .public) recovery=preserve-registration"
      )
    }
  }

  private func finish(
    _ resolvedOutcome: SystemHelperFanResetOutcome,
    finisher: Finisher,
    logWinner: () -> Void
  ) {
    let resolution = lock.withLock { () -> SystemHelperFanResetResolution? in
      guard self.outcome == nil else {
        return nil
      }
      outcome = resolvedOutcome
      let resolution = SystemHelperFanResetResolution(
        continuation: continuation,
        deadlineTask: deadlineTask,
        resetTask: resetTask
      )
      self.continuation = nil
      resetTask = nil
      deadlineTask = nil
      return resolution
    }
    guard let resolution else { return }
    logWinner()
    if finisher != .reset { resolution.resetTask?.cancel() }
    if finisher != .deadline { resolution.deadlineTask?.cancel() }
    resolution.continuation?.resume(returning: resolvedOutcome)
  }
}

// MARK: - SystemHelperFanResetSequencer

enum SystemHelperFanResetSequencer {
  static let deadlineSeconds: TimeInterval = 3

  static func resetWithinDeadline(
    deadline: TimeInterval = deadlineSeconds,
    resetFans: @escaping @Sendable () async throws -> Void
  ) async -> SystemHelperFanResetOutcome {
    log.notice(
      "system_helper.reset.started deadlineSeconds=\(deadline, privacy: .public)"
    )
    let completion = SystemHelperFanResetCompletion()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        completion.install(continuation)
        let resetTask = Task {
          do {
            try await resetFans()
            completion.finishReset(.completed)
          } catch {
            log.notice(
              "system_helper.reset.operation_failed error=\(error.localizedDescription, privacy: .public) recovery=resolve-race"
            )
            completion.finishReset(.failed(reason: error.localizedDescription))
          }
        }
        let deadlineTask = Task {
          let clock = ContinuousClock()
          do {
            try await clock.sleep(for: .seconds(deadline))
          } catch {
            log.notice(
              "system_helper.reset.deadline_cancelled recovery=stop-deadline"
            )
            return
          }
          completion.finishDeadline(deadline: deadline)
        }
        completion.installTasks(
          resetTask: resetTask,
          deadlineTask: deadlineTask
        )
      }
    } onCancel: {
      completion.cancel()
    }
  }
}
