//
//  TestControlAtomicWriteProbe.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - TestControlAdapterTestError

enum TestControlAdapterTestError: Error, Equatable {
  case acknowledgmentWrite
  case synchronization
}

// MARK: - TestControlAtomicWriteProbe

final class TestControlAtomicWriteProbe: @unchecked Sendable {
  private let lock = NSLock()
  private let failingAcknowledgmentRevision: TestControlRevision
  private var storedFailingRevisionAttemptCount = 0

  init(failingAcknowledgmentRevision: UInt64) {
    self.failingAcknowledgmentRevision = TestControlRevision(
      failingAcknowledgmentRevision
    )
  }

  var failingRevisionAttemptCount: Int {
    lock.lock()
    let count = storedFailingRevisionAttemptCount
    lock.unlock()
    return count
  }

  func write(_ data: Data, to url: URL) throws {
    var isTargetAcknowledgment = false
    if url.lastPathComponent == TestControlFile.acknowledgment(for: .app) {
      let acknowledgment = try TestControlCodec.decode(
        TestControlAcknowledgment.self,
        from: data
      )
      isTargetAcknowledgment =
        acknowledgment.revision == failingAcknowledgmentRevision
    }
    if isTargetAcknowledgment {
      lock.lock()
      storedFailingRevisionAttemptCount += 1
      let shouldFail = storedFailingRevisionAttemptCount == 1
      lock.unlock()
      if shouldFail {
        throw TestControlAdapterTestError.acknowledgmentWrite
      }
    }
    try data.write(to: url, options: [.atomic])
  }
}
