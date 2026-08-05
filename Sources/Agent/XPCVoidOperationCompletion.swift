//
//  XPCVoidOperationCompletion.swift
//  FanCurveAgent
//
//  Created by Codex <noreply@openai.com> on 2026-08-05.
//  Copyright © 2026, all rights reserved.
//

import Foundation

final class XPCVoidOperationCompletion: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Error>?
  private var operationTask: Task<Void, Never>?
  private var result: Result<Void, Error>?

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

  func install(operationTask: Task<Void, Never>) {
    let shouldCancel = lock.withLock {
      guard result == nil else { return true }
      self.operationTask = operationTask
      return false
    }
    if shouldCancel {
      operationTask.cancel()
    }
  }

  @discardableResult
  func finish(with resolution: Result<Void, Error>) -> Bool {
    let completion = lock.withLock {
      guard result == nil else {
        return XPCVoidOperationResolution(didFinish: false)
      }
      result = resolution
      let completion = XPCVoidOperationResolution(
        didFinish: true,
        continuation: continuation,
        operationTask: operationTask
      )
      continuation = nil
      operationTask = nil
      return completion
    }
    completion.operationTask?.cancel()
    completion.continuation?.resume(with: resolution)
    return completion.didFinish
  }
}

// MARK: - XPCVoidOperationResolution

private struct XPCVoidOperationResolution {
  let continuation: CheckedContinuation<Void, Error>?
  let operationTask: Task<Void, Never>?
  let didFinish: Bool

  init(
    didFinish: Bool,
    continuation: CheckedContinuation<Void, Error>? = nil,
    operationTask: Task<Void, Never>? = nil
  ) {
    self.continuation = continuation
    self.operationTask = operationTask
    self.didFinish = didFinish
  }
}
