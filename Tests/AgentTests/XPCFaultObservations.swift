//
//  XPCFaultObservations.swift
//  FanCurveAgentTests
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let controlledXPCTestLog = AppLog.make(category: "ControlledXPCTests")

// MARK: - XPCFaultEvidenceReader

final class XPCFaultEvidenceReader: @unchecked Sendable {
  private let store: TestControlSessionStore

  init(store: TestControlSessionStore) {
    self.store = store
  }

  func contains(
    participant: TestControlParticipant,
    fault: TestXPCFault
  ) -> Bool {
    do {
      let events = try store.loadEvents(for: participant)
      return events.contains { event in
        event.payload == .xpcFault(fault)
      }
    } catch {
      controlledXPCTestLog.error(
        "test_control.xpc.evidence_read_failed participant=\(participant.rawValue, privacy: .public) fault=\(fault.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=report-missing-evidence"
      )
      return false
    }
  }
}

// MARK: - XPCFaultObserver

final class XPCFaultObserver: @unchecked Sendable {
  private let reader: XPCFaultEvidenceReader
  private let observations: XPCFaultObservations
  private let participant: TestControlParticipant

  init(
    reader: XPCFaultEvidenceReader,
    observations: XPCFaultObservations,
    participant: TestControlParticipant
  ) {
    self.reader = reader
    self.observations = observations
    self.participant = participant
  }

  func observe(_ fault: TestXPCFault) {
    let wasRecorded = reader.contains(participant: participant, fault: fault)
    observations.recordEvidence(wasRecorded, fault: fault)
  }

  func recordInterruptionTermination() {
    let wasRecorded = reader.contains(participant: .agent, fault: .interruption)
    observations.recordProcessTermination(evidenceWasRecorded: wasRecorded)
  }
}

// MARK: - XPCConnectionCounter

final class XPCConnectionCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.withLock { count }
  }

  func increment() {
    lock.withLock {
      count += 1
    }
  }
}

// MARK: - XPCConnectionRegistry

final class XPCConnectionRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var connections: [NSXPCConnection] = []

  func append(_ connection: NSXPCConnection) {
    lock.withLock {
      connections.append(connection)
    }
  }

  func invalidateMostRecent() {
    let connection = lock.withLock {
      connections.last
    }
    connection?.invalidate()
  }
}

// MARK: - XPCRequestDispatchController

@MainActor
final class XPCRequestDispatchController: AgentXPCRequestDispatching {
  private var isSuspended = false
  private var pendingOperations: [@MainActor () -> Void] = []

  var pendingOperationCount: Int {
    pendingOperations.count
  }

  func dispatch(_ operation: @escaping @MainActor () -> Void) {
    if isSuspended {
      pendingOperations.append(operation)
      return
    }
    operation()
  }

  func suspend() {
    isSuspended = true
  }

  func resumeNext() {
    guard !pendingOperations.isEmpty else {
      return
    }
    let operation = pendingOperations.removeFirst()
    operation()
  }
}

// MARK: - XPCProxyErrorHandlerRecorder

@MainActor
final class XPCProxyErrorHandlerRecorder: AgentXPCRemoteProxyProviding {
  private var handlers: [@Sendable (Error) -> Void] = []
  private var retainedHandler: (@Sendable (Error) -> Void)?

  func remoteProxy(
    for connection: NSXPCConnection,
    errorHandler: @escaping @Sendable (Error) -> Void
  ) -> FanCurveAgentXPCProtocol? {
    handlers.append(errorHandler)
    return connection.remoteObjectProxyWithErrorHandler(errorHandler)
      as? FanCurveAgentXPCProtocol
  }

  func retainMostRecentHandler() -> Bool {
    retainedHandler = handlers.last
    return retainedHandler != nil
  }

  func triggerRetainedHandler() {
    retainedHandler?(
      NSError(
        domain: "ControlledXPCStaleProxyError",
        code: 1
      )
    )
  }
}

// MARK: - XPCConnectionFactory

@MainActor
final class XPCConnectionFactory {
  private weak var listener: NSXPCListener?
  private let counter: XPCConnectionCounter
  private let registry: XPCConnectionRegistry

  init(
    listener: NSXPCListener,
    counter: XPCConnectionCounter,
    registry: XPCConnectionRegistry
  ) {
    self.listener = listener
    self.counter = counter
    self.registry = registry
  }

  func makeConnection() -> NSXPCConnection {
    guard let listener else {
      return NSXPCConnection(machServiceName: "invalid", options: [])
    }
    counter.increment()
    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    registry.append(connection)
    return connection
  }
}

// MARK: - XPCFaultObservations

final class XPCFaultObservations: @unchecked Sendable {
  private let lock = NSLock()
  private var storedEvidenceByFault: [TestXPCFault: Bool] = [:]
  private var storedProcessTerminationCount = 0

  var evidenceByFault: [TestXPCFault: Bool] {
    lock.withLock { storedEvidenceByFault }
  }

  var processTerminationCount: Int {
    lock.withLock { storedProcessTerminationCount }
  }

  func recordEvidence(_ wasRecorded: Bool, fault: TestXPCFault) {
    lock.withLock {
      storedEvidenceByFault[fault] = wasRecorded
    }
  }

  func recordProcessTermination(evidenceWasRecorded: Bool) {
    lock.withLock {
      storedProcessTerminationCount += 1
      storedEvidenceByFault[.interruption] = evidenceWasRecorded
    }
  }
}

// MARK: - XPCFallbackService

final class XPCFallbackService:
  BackgroundAgentServiceManaging,
  HelperServiceManaging
{
  var status: ManagedServiceStatus {
    .enabled
  }

  func register() {
    _ = status
  }

  func unregister() {
    _ = status
  }

  func openSystemSettings() {
    _ = status
  }
}

// MARK: - XPCFallbackHardware

final class XPCFallbackHardware: FanHardware, @unchecked Sendable {
  func shutdown() {
    _ = Self.self
  }

  func readAndApply(
    fanCount _: UInt,
    tempKeys _: [String],
    setFans _: [(index: UInt, rpm: Float)],
    autoFans _: [UInt],
    priority _: Int?
  ) -> FanHardwareBatchRead {
    FanHardwareBatchRead(fans: [], temps: [:])
  }

  func enumerateKeys() -> [String] {
    []
  }

  func getOwnership() -> [AgentOwnershipEntry] {
    []
  }

  func setFanRPM(
    _: UInt,
    rpm _: Float,
    priority _: Int?
  ) {
    _ = Self.self
  }

  func setFanAuto(
    _: UInt,
    priority _: Int?
  ) {
    _ = Self.self
  }
}
