//
//  XPCProbeCompletion.swift
//  FanCurveAgent
//
//  Created by Codex <noreply@openai.com> on 2026-08-04.
//  Copyright © 2026, all rights reserved.
//

import Foundation

final class XPCProbeCompletion: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Error>?
  private var operationTask: Task<Void, Never>?
  private var result: Result<Void, Error>?
  private var timeoutTask: Task<Void, Never>?

  func install(_ continuation: CheckedContinuation<Void, Error>) {
    let pendingResult = lock.withLock { () -> Result<Void, Error>? in
      if let storedResult = result { return storedResult }
      self.continuation = continuation
      return nil
    }
    if let pendingResult {
      continuation.resume(with: pendingResult)
    }
  }

  func installTasks(
    operationTask: Task<Void, Never>,
    timeoutTask: Task<Void, Never>
  ) {
    let shouldCancel = lock.withLock {
      guard result == nil else { return true }
      self.operationTask = operationTask
      self.timeoutTask = timeoutTask
      return false
    }
    if shouldCancel {
      operationTask.cancel()
      timeoutTask.cancel()
    }
  }

  @discardableResult
  func finish(with resolution: Result<Void, Error>) -> Bool {
    let completion = lock.withLock {
      guard self.result == nil else {
        return XPCProbeResolution(didFinish: false)
      }
      result = resolution
      let completion = XPCProbeResolution(
        didFinish: true,
        continuation: continuation,
        operationTask: operationTask,
        timeoutTask: timeoutTask
      )
      continuation = nil
      operationTask = nil
      timeoutTask = nil
      return completion
    }
    completion.operationTask?.cancel()
    completion.timeoutTask?.cancel()
    completion.continuation?.resume(with: resolution)
    return completion.didFinish
  }
}

// MARK: - XPCProbeResolution

private struct XPCProbeResolution {
  let continuation: CheckedContinuation<Void, Error>?
  let operationTask: Task<Void, Never>?
  let timeoutTask: Task<Void, Never>?
  let didFinish: Bool

  init(
    didFinish: Bool,
    continuation: CheckedContinuation<Void, Error>? = nil,
    operationTask: Task<Void, Never>? = nil,
    timeoutTask: Task<Void, Never>? = nil
  ) {
    self.continuation = continuation
    self.operationTask = operationTask
    self.timeoutTask = timeoutTask
    self.didFinish = didFinish
  }
}
