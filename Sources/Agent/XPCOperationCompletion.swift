//
//  XPCOperationCompletion.swift
//  FanCurveAgent
//
//  Created by Codex <noreply@openai.com> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation

final class XPCOperationCompletion: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Error>?
  private var result: Result<Void, Error>?
  private var tasks: [Task<Void, Never>] = []

  func install(_ continuation: CheckedContinuation<Void, Error>) {
    let pendingResult = lock.withLock { () -> Result<Void, Error>? in
      if let result { return result }
      self.continuation = continuation
      return nil
    }
    if let pendingResult {
      continuation.resume(with: pendingResult)
    }
  }

  func install(tasks: [Task<Void, Never>]) {
    let shouldCancel = lock.withLock {
      guard result == nil else { return true }
      self.tasks = tasks
      return false
    }
    guard shouldCancel else { return }
    for task in tasks {
      task.cancel()
    }
  }

  @discardableResult
  func finish(with resolution: Result<Void, Error>) -> Bool {
    let completion = lock.withLock { () -> XPCOperationResolution? in
      guard result == nil else { return nil }
      result = resolution
      let completion = XPCOperationResolution(
        continuation: continuation,
        tasks: tasks
      )
      continuation = nil
      tasks = []
      return completion
    }
    guard let completion else { return false }
    for task in completion.tasks {
      task.cancel()
    }
    completion.continuation?.resume(with: resolution)
    return true
  }
}

// MARK: - XPCOperationResolution

private struct XPCOperationResolution {
  let continuation: CheckedContinuation<Void, Error>?
  let tasks: [Task<Void, Never>]
}
