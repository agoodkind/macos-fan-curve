//
//  TestControlSessionStore+Wait.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import AppLog
  import Darwin
  import Foundation

  private let testControlWaitLog = AppLog.make(category: "TestControlWait")

  private struct TestControlFileObservation {
    let signal: DispatchSemaphore
    let cancellation: DispatchSemaphore
    let source: DispatchSourceFileSystemObject

    init(url: URL) throws {
      let descriptor = Darwin.open(url.path, O_EVTONLY)
      guard descriptor >= 0 else {
        throw POSIXError(.init(rawValue: errno) ?? .EIO)
      }
      let eventSignal = DispatchSemaphore(value: 0)
      let cancellationSignal = DispatchSemaphore(value: 0)
      let fileSource = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: descriptor,
        eventMask: [.delete, .extend, .rename, .revoke, .write],
        queue: DispatchQueue.global(qos: .userInitiated)
      )
      fileSource.setEventHandler {
        eventSignal.signal()
      }
      fileSource.setCancelHandler {
        _ = Darwin.close(descriptor)
        cancellationSignal.signal()
      }
      signal = eventSignal
      cancellation = cancellationSignal
      source = fileSource
    }

    func start() {
      source.resume()
    }

    func wait(until deadline: DispatchTime) -> DispatchTimeoutResult {
      signal.wait(timeout: deadline)
    }

    func stop() {
      source.cancel()
      cancellation.wait()
    }
  }

  private struct TestControlWaitMatch<Value> {
    let value: Value
    let observation: String
  }

  private struct TestControlWaitContext {
    let fileURL: URL
    let deadline: DispatchTime
    let description: String
    let timeout: TimeInterval
  }

  extension TestControlSessionStore {
    func waitForAcknowledgment(
      participant: TestControlParticipant,
      revision: UInt64,
      timeout: TimeInterval,
      onObservationReady: (@Sendable () -> Void)? = nil
    ) throws -> TestControlAcknowledgment {
      let requestedRevision = TestControlRevision(revision)
      let condition =
        "ack participant=\(participant.rawValue) revision=\(requestedRevision.value)"
      return try waitForFileCondition(
        fileURL: acknowledgmentURL(for: participant),
        description: condition,
        timeout: timeout,
        onObservationReady: onObservationReady
      ) {
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
      timeout: TimeInterval,
      onObservationReady: (@Sendable () -> Void)? = nil
    ) throws -> TestControlEvent {
      let requestedRevision = TestControlRevision(revision)
      let condition =
        "event participant=\(participant.rawValue) kind=\(kind.rawValue) revision=\(revision)"
      return try waitForFileCondition(
        fileURL: eventsURL(for: participant),
        description: condition,
        timeout: timeout,
        onObservationReady: onObservationReady
      ) {
        try loadEvents(for: participant).first { event in
          event.kind == kind && event.revision >= requestedRevision
        }
      }
    }

    private func waitForFileCondition<Value>(
      fileURL: URL,
      description: String,
      timeout: TimeInterval,
      onObservationReady: (@Sendable () -> Void)?,
      condition: () throws -> Value?
    ) throws -> Value {
      guard timeout > 0, timeout.isFinite else {
        throw TestControlError.invalidArguments("Wait timeout must be positive and finite")
      }
      let context = TestControlWaitContext(
        fileURL: fileURL,
        deadline: DispatchTime.now() + timeout,
        description: description,
        timeout: timeout
      )
      testControlWaitLog.info(
        "test_control.wait.started condition=\(description, privacy: .public) timeout_seconds=\(timeout, privacy: .public)"
      )
      if let value = try evaluate(
        condition: condition,
        context: context
      ) {
        return completeWait(
          value,
          description: description,
          observation: "immediate"
        )
      }

      var observationReadyWasReported = false
      while DispatchTime.now() < context.deadline {
        if let match = try observeFileCondition(
          context: context,
          observationReadyWasReported: &observationReadyWasReported,
          onObservationReady: onObservationReady,
          condition: condition
        ) {
          return completeWait(
            match.value,
            description: description,
            observation: match.observation
          )
        }
      }

      throw timeoutError(description: description, timeout: timeout)
    }

    private func observeFileCondition<Value>(
      context: TestControlWaitContext,
      observationReadyWasReported: inout Bool,
      onObservationReady: (@Sendable () -> Void)?,
      condition: () throws -> Value?
    ) throws -> TestControlWaitMatch<Value>? {
      guard DispatchTime.now() < context.deadline else {
        throw timeoutError(
          description: context.description,
          timeout: context.timeout
        )
      }
      let observation = try makeObservation(for: context.fileURL)
      observation.start()
      defer {
        observation.stop()
      }
      if !observationReadyWasReported {
        onObservationReady?()
        observationReadyWasReported = true
      }
      if let value = try evaluate(
        condition: condition,
        context: context
      ) {
        return TestControlWaitMatch(
          value: value,
          observation: "post-subscription"
        )
      }
      guard observation.wait(until: context.deadline) == .success else {
        return nil
      }
      testControlWaitLog.debug(
        "test_control.wait.filesystem_event condition=\(context.description, privacy: .public)"
      )
      guard
        let value = try evaluate(
          condition: condition,
          context: context
        )
      else {
        return nil
      }
      return TestControlWaitMatch(
        value: value,
        observation: "filesystem-event"
      )
    }

    private func makeObservation(
      for fileURL: URL
    ) throws -> TestControlFileObservation {
      if FileManager.default.fileExists(atPath: fileURL.path) {
        do {
          return try TestControlFileObservation(url: fileURL)
        } catch let error as POSIXError where error.code == .ENOENT {
          testControlWaitLog.debug(
            "test_control.wait.file_replaced path=\(fileURL.path, privacy: .public) recovery=observe-directory"
          )
          return try TestControlFileObservation(url: directory)
        }
      }
      return try TestControlFileObservation(url: directory)
    }

    private func completeWait<Value>(
      _ value: Value,
      description: String,
      observation: String
    ) -> Value {
      testControlWaitLog.info(
        "test_control.wait.completed condition=\(description, privacy: .public) observation=\(observation, privacy: .public)"
      )
      return value
    }

    private func evaluate<Value>(
      condition: () throws -> Value?,
      context: TestControlWaitContext
    ) throws -> Value? {
      guard DispatchTime.now() < context.deadline else {
        throw timeoutError(
          description: context.description,
          timeout: context.timeout
        )
      }
      let value = try condition()
      guard DispatchTime.now() < context.deadline else {
        throw timeoutError(
          description: context.description,
          timeout: context.timeout
        )
      }
      return value
    }

    private func timeoutError(
      description: String,
      timeout: TimeInterval
    ) -> TestControlError {
      testControlWaitLog.error(
        "test_control.wait.timed_out condition=\(description, privacy: .public) timeout_seconds=\(timeout, privacy: .public) recovery=return-timeout"
      )
      return TestControlError.timeout(description)
    }
  }
#endif
