//
//  TestControlSessionStore+Wait.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import AppLog
  import Darwin
  import Foundation

  private let testControlWaitLog = AppLog.make(category: "TestControlWait")

  extension TestControlSessionStore {
    func waitForAcknowledgment(
      participant: TestControlParticipant,
      revision: UInt64,
      timeout: TimeInterval
    ) throws -> TestControlAcknowledgment {
      let requestedRevision = TestControlRevision(revision)
      let condition =
        "ack participant=\(participant.rawValue) revision=\(requestedRevision.value)"
      return try waitForFileCondition(description: condition, timeout: timeout) {
        guard let acknowledgment = try loadAcknowledgment(for: participant) else {
          return nil
        }
        guard acknowledgment.revision >= requestedRevision else {
          return nil
        }
        return acknowledgment
      }
    }

    func waitForEvent(
      participant: TestControlParticipant,
      kind: TestControlEventKind,
      revision: UInt64,
      timeout: TimeInterval
    ) throws -> TestControlEvent {
      let requestedRevision = TestControlRevision(revision)
      let condition =
        "event participant=\(participant.rawValue) kind=\(kind.rawValue) revision=\(revision)"
      return try waitForFileCondition(description: condition, timeout: timeout) {
        try loadEvents(for: participant).first { event in
          event.kind == kind && event.revision >= requestedRevision
        }
      }
    }

    private func waitForFileCondition<Value>(
      description: String,
      timeout: TimeInterval,
      condition: () throws -> Value?
    ) throws -> Value {
      guard timeout > 0, timeout.isFinite else {
        throw TestControlError.invalidArguments("Wait timeout must be positive and finite")
      }
      testControlWaitLog.info(
        "test_control.wait.started condition=\(description, privacy: .public) timeout_seconds=\(timeout, privacy: .public)"
      )
      if let value = try condition() {
        testControlWaitLog.info(
          "test_control.wait.completed condition=\(description, privacy: .public) observation=immediate"
        )
        return value
      }

      let descriptor = Darwin.open(directory.path, O_EVTONLY)
      guard descriptor >= 0 else {
        let error = POSIXError(.init(rawValue: errno) ?? .EIO)
        testControlWaitLog.error(
          "test_control.wait.observe_failed path=\(directory.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=abort-wait"
        )
        throw error
      }
      let signal = DispatchSemaphore(value: 0)
      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: descriptor,
        eventMask: [.delete, .extend, .rename, .write],
        queue: DispatchQueue.global(qos: .userInitiated)
      )
      source.setEventHandler {
        testControlWaitLog.debug(
          "test_control.wait.filesystem_event condition=\(description, privacy: .public)"
        )
        signal.signal()
      }
      source.setCancelHandler {
        _ = Darwin.close(descriptor)
      }
      source.resume()
      defer {
        source.cancel()
      }

      if let value = try condition() {
        testControlWaitLog.info(
          "test_control.wait.completed condition=\(description, privacy: .public) observation=post-subscription"
        )
        return value
      }

      let deadline = DispatchTime.now() + timeout
      while signal.wait(timeout: deadline) == .success {
        if let value = try condition() {
          testControlWaitLog.info(
            "test_control.wait.completed condition=\(description, privacy: .public) observation=filesystem-event"
          )
          return value
        }
      }

      testControlWaitLog.error(
        "test_control.wait.timed_out condition=\(description, privacy: .public) timeout_seconds=\(timeout, privacy: .public) recovery=return-timeout"
      )
      throw TestControlError.timeout(description)
    }
  }
#endif
