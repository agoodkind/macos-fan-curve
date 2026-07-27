//
//  TestControlRuntime.swift
//  FanCurve
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import AppLog
  import Darwin
  import Dispatch
  import Foundation

  private let testControlRuntimeLog = AppLog.make(category: "TestControlRuntime")

  struct TestControlOperationError: Error, Equatable, LocalizedError, Sendable {
    let code: String
    let message: String

    var errorDescription: String? {
      "\(code): \(message)"
    }
  }

  final class TestControlRuntime: @unchecked Sendable {
    let store: TestControlSessionStore
    let participant: TestControlParticipant

    private let lock = NSLock()
    private let faultLock = NSLock()
    private let monitorLock = NSLock()
    private let monitorQueue: DispatchQueue
    private let monitorCancellationGroup = DispatchGroup()
    private var appliedState: TestControlState
    private var pendingAcknowledgment: TestControlAcknowledgment?
    private var consumedFaults: Set<String> = []
    private var monitorSource: DispatchSourceFileSystemObject?

    init(
      store: TestControlSessionStore,
      participant: TestControlParticipant
    ) throws {
      self.store = store
      self.participant = participant
      self.monitorQueue = DispatchQueue(
        label: "io.goodkind.fancurve.test-control.\(participant.rawValue)"
      )
      let initialState = try store.loadState()
      self.appliedState = initialState
      try store.writeAcknowledgment(
        TestControlAcknowledgment(
          sessionID: initialState.sessionID,
          revision: initialState.revision.value,
          participant: participant
        )
      )
      testControlRuntimeLog.notice(
        "test_control.runtime.activated participant=\(participant.rawValue, privacy: .public) session=\(initialState.sessionID.uuidString, privacy: .public) revision=\(initialState.revision.value, privacy: .public)"
      )
      try startMonitoring()
    }

    deinit {
      monitorSource?.cancel()
    }

    func stopMonitoring() {
      let source = monitorLock.withLock {
        let source = monitorSource
        monitorSource = nil
        return source
      }
      guard let source else {
        return
      }
      source.cancel()
      monitorCancellationGroup.wait()
      testControlRuntimeLog.info(
        "test_control.runtime.monitor_stopped participant=\(participant.rawValue, privacy: .public) path=\(store.directory.path, privacy: .public)"
      )
    }

    func refresh() throws -> TestControlState {
      lock.lock()
      defer { lock.unlock() }

      let proposedState = try store.loadState()
      guard proposedState.sessionID == appliedState.sessionID else {
        testControlRuntimeLog.error(
          "test_control.runtime.session_rejected participant=\(participant.rawValue, privacy: .public) current=\(appliedState.sessionID.uuidString, privacy: .public) proposed=\(proposedState.sessionID.uuidString, privacy: .public) recovery=preserve-applied-state"
        )
        throw TestControlError.invalidSession(
          expected: appliedState.sessionID,
          actual: proposedState.sessionID
        )
      }
      if proposedState.revision < appliedState.revision {
        let currentRevision = appliedState.revision.value
        let proposedRevision = proposedState.revision.value
        let event = TestControlEvent(
          sessionID: appliedState.sessionID,
          revision: currentRevision,
          participant: participant,
          payload: .revisionRejected(
            applied: currentRevision,
            proposed: proposedRevision
          )
        )
        try store.appendRuntimeEvent(event, validatingAgainst: appliedState)
        testControlRuntimeLog.error(
          "test_control.runtime.revision_rejected participant=\(participant.rawValue, privacy: .public) current=\(currentRevision, privacy: .public) proposed=\(proposedRevision, privacy: .public) recovery=preserve-applied-state"
        )
        throw TestControlError.revisionNotIncreasing(
          current: currentRevision,
          proposed: proposedRevision
        )
      }
      guard proposedState.revision > appliedState.revision else {
        try retryPendingAcknowledgment(for: proposedState.revision)
        testControlRuntimeLog.debug(
          "test_control.runtime.revision_idempotent participant=\(participant.rawValue, privacy: .public) revision=\(proposedState.revision.value, privacy: .public)"
        )
        return appliedState
      }

      appliedState = proposedState
      let acknowledgment = TestControlAcknowledgment(
        sessionID: proposedState.sessionID,
        revision: proposedState.revision.value,
        participant: participant
      )
      pendingAcknowledgment = acknowledgment
      do {
        try store.writeAcknowledgment(acknowledgment)
        pendingAcknowledgment = nil
      } catch {
        testControlRuntimeLog.error(
          "test_control.runtime.acknowledgment_pending participant=\(participant.rawValue, privacy: .public) revision=\(proposedState.revision.value, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=retry-on-equal-revision"
        )
        throw error
      }
      testControlRuntimeLog.notice(
        "test_control.runtime.revision_applied participant=\(participant.rawValue, privacy: .public) revision=\(proposedState.revision.value, privacy: .public)"
      )
      return proposedState
    }

    func record(
      _ payload: TestControlEventPayload,
      state: TestControlState? = nil
    ) throws {
      let currentState: TestControlState
      if let state {
        currentState = state
      } else {
        currentState = try refresh()
      }
      try store.appendEvent(
        TestControlEvent(
          sessionID: currentState.sessionID,
          revision: currentState.revision.value,
          participant: participant,
          payload: payload
        )
      )
    }

    func consumeFault(_ fault: TestXPCFault) throws -> Bool {
      let currentState = try refresh()
      guard currentState.xpcFault == fault else {
        return false
      }

      let faultKey = "\(currentState.revision.value):\(fault.rawValue)"
      return try faultLock.withLock {
        guard !consumedFaults.contains(faultKey) else {
          return false
        }
        try record(.xpcFault(fault), state: currentState)
        consumedFaults.insert(faultKey)
        testControlRuntimeLog.notice(
          "test_control.runtime.fault_consumed participant=\(participant.rawValue, privacy: .public) fault=\(fault.rawValue, privacy: .public) revision=\(currentState.revision.value, privacy: .public)"
        )
        return true
      }
    }

    private func retryPendingAcknowledgment(
      for revision: TestControlRevision
    ) throws {
      guard let acknowledgment = pendingAcknowledgment else {
        return
      }
      guard acknowledgment.revision == revision else {
        return
      }
      testControlRuntimeLog.notice(
        "test_control.runtime.acknowledgment_retry.started participant=\(participant.rawValue, privacy: .public) revision=\(revision.value, privacy: .public)"
      )
      do {
        try store.writeAcknowledgment(acknowledgment)
        pendingAcknowledgment = nil
        testControlRuntimeLog.notice(
          "test_control.runtime.acknowledgment_retry.completed participant=\(participant.rawValue, privacy: .public) revision=\(revision.value, privacy: .public)"
        )
      } catch {
        testControlRuntimeLog.error(
          "test_control.runtime.acknowledgment_retry.failed participant=\(participant.rawValue, privacy: .public) revision=\(revision.value, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=retain-pending-acknowledgment"
        )
        throw error
      }
    }

    private func startMonitoring() throws {
      let descriptor = Darwin.open(store.directory.path, O_EVTONLY)
      guard descriptor >= 0 else {
        throw POSIXError(.init(rawValue: errno) ?? .EIO)
      }
      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: descriptor,
        eventMask: [.attrib, .delete, .extend, .rename, .write],
        queue: monitorQueue
      )
      let cancellationGroup = monitorCancellationGroup
      cancellationGroup.enter()
      source.setEventHandler { [weak self] in
        guard let self else { return }
        do {
          _ = try refresh()
        } catch {
          testControlRuntimeLog.error(
            "test_control.runtime.monitor_refresh_failed participant=\(participant.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=preserve-applied-state"
          )
        }
      }
      source.setCancelHandler {
        _ = Darwin.close(descriptor)
        cancellationGroup.leave()
      }
      monitorLock.withLock {
        monitorSource = source
      }
      source.resume()
      testControlRuntimeLog.info(
        "test_control.runtime.monitor_started participant=\(participant.rawValue, privacy: .public) path=\(store.directory.path, privacy: .public)"
      )
    }
  }
#endif
