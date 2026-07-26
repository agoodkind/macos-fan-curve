//
//  FanCurveAgentClient.swift
//  FanCurve
//
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Combine
import Foundation

let fanCurveAgentClientLog = AppLog.make(category: "FanCurveAgentClient")

enum FanCurveAgentClientConstants {
  static let snapshotFreshnessWindow: TimeInterval = 5
}

@MainActor
final class FanCurveAgentClient: NSObject, ObservableObject, FanCurveAgentXPCEventProtocol {
  @Published private(set) var connectionState: FanCurveAgentConnectionState = .disconnected
  @Published private(set) var runtimeState: RuntimeState = .fromSharedDefaultsSnapshot(nil)
  @Published private(set) var snapshot: AgentSnapshot?
  @Published private(set) var lastError: String?

  private var connection: NSXPCConnection?
  private var connectionTask: Task<Void, Never>?
  private var reconnectTask: Task<Void, Never>?
  private let serviceName: String
  private let connectionFactory: @MainActor () -> NSXPCConnection
  private let control: any FanCurveAgentClientControlling
  private let reconnectDelay: TimeInterval
  private let requestDispatcher: any AgentXPCRequestDispatching
  private let remoteProxyProvider: any AgentXPCRemoteProxyProviding
  private let commandTransport = AgentCommandTransport()
  private let decoder = JSONDecoder()
  private var pendingRequests: [UUID: AgentXPCReplyResumer] = [:]
  private var stopped = false
  private var connectionGeneration: UInt64 = 0

  var pendingRequestCount: Int {
    pendingRequests.count
  }

  init(
    serviceName: String = FanCurveAgentXPC.serviceName,
    connectionFactory: (@MainActor () -> NSXPCConnection)? = nil,
    control: any FanCurveAgentClientControlling =
      ProductionAgentClientControl(),
    reconnectDelay: TimeInterval = 1,
    requestDispatcher: any AgentXPCRequestDispatching =
      ImmediateAgentXPCRequestDispatcher(),
    remoteProxyProvider: any AgentXPCRemoteProxyProviding =
      NSXPCRemoteProxyProvider()
  ) {
    self.serviceName = serviceName
    self.connectionFactory =
      connectionFactory ?? {
        NSXPCConnection(machServiceName: serviceName, options: [])
      }
    self.control = control
    self.reconnectDelay = reconnectDelay
    self.requestDispatcher = requestDispatcher
    self.remoteProxyProvider = remoteProxyProvider
    super.init()
  }

  func start() {
    guard connection == nil else { return }
    stopped = false
    connect()
  }

  func stop() {
    stopped = true
    connectionTask?.cancel()
    connectionTask = nil
    reconnectTask?.cancel()
    reconnectTask = nil
    cancelPendingRequests(reason: "client-stop")
    let activeConnection = connection
    connection = nil
    activeConnection?.interruptionHandler = nil
    activeConnection?.invalidationHandler = nil
    activeConnection?.invalidate()
    connectionState = .disconnected
    fanCurveAgentClientLog.info("agent_client.connection.stopped")
  }

  nonisolated func agentRuntimeStateDidUpdate(_ stateData: Data) {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      do {
        let state = try decoder.decode(RuntimeState.self, from: stateData)
        control.recordEvent(.runtimeEventAccepted)
        apply(runtimeState: state)
      } catch {
        control.recordEvent(.runtimeEventRejected)
        lastError = error.localizedDescription
        fanCurveAgentClientLog.error(
          "agent_client.state.decode_failed error=\(error.localizedDescription, privacy: .public) recovery=keep-last-state"
        )
      }
    }
  }

  private func connect() {
    guard !stopped else { return }
    guard connectionIsAllowed() else {
      return
    }
    connectionState = .connecting
    control.recordEvent(.connecting)
    let nextConnection = connectionFactory()
    connectionGeneration += 1
    let nextConnectionGeneration = connectionGeneration
    configure(nextConnection, generation: nextConnectionGeneration)
    connection = nextConnection
    nextConnection.resume()
    fanCurveAgentClientLog.notice(
      "agent_client.connection.started service=\(serviceName, privacy: .public)")
    if control.consumeReconnectFault() {
      fanCurveAgentClientLog.notice(
        "agent_client.connection.fault_injected kind=reconnect recovery=invalidate-connection"
      )
      nextConnection.invalidate()
      return
    }
    startConnectionTask(
      nextConnection: nextConnection,
      generation: nextConnectionGeneration
    )
  }

  private func configure(
    _ nextConnection: NSXPCConnection,
    generation: UInt64
  ) {
    nextConnection.remoteObjectInterface = NSXPCInterface(with: FanCurveAgentXPCProtocol.self)
    nextConnection.exportedInterface = NSXPCInterface(with: FanCurveAgentXPCEventProtocol.self)
    nextConnection.exportedObject = self
    nextConnection.interruptionHandler = { @Sendable [weak self] in
      DispatchQueue.main.async {
        self?.handleDisconnect(generation, reason: "interrupted")
      }
    }
    nextConnection.invalidationHandler = { @Sendable [weak self] in
      DispatchQueue.main.async {
        self?.handleDisconnect(generation, reason: "invalidated")
      }
    }
  }

  private func startConnectionTask(
    nextConnection: NSXPCConnection,
    generation: UInt64
  ) {
    connectionTask = Task { @MainActor [weak self] in
      guard let self else {
        return
      }
      do {
        try await registerForEvents()
        try await refreshCurrentState()
        guard
          !Task.isCancelled,
          !stopped,
          connectionGeneration == generation
        else {
          return
        }
        connectionTask = nil
        connectionState = .connected
        control.recordEvent(.connected)
        lastError = nil
        fanCurveAgentClientLog.notice("agent_client.connection.ready")
      } catch {
        guard !stopped, connectionGeneration == generation else {
          return
        }
        connectionTask = nil
        connection = nil
        nextConnection.invalidate()
        lastError = error.localizedDescription
        connectionState = .failed(error.localizedDescription)
        fanCurveAgentClientLog.notice(
          "agent_client.connection.failed error=\(error.localizedDescription, privacy: .public) recovery=schedule-reconnect"
        )
        scheduleReconnect()
      }
    }
  }
}

extension FanCurveAgentClient {
  private func registerForEvents() async throws {
    _ = try await performRequest(.registerEvents)
    fanCurveAgentClientLog.debug("agent_client.events.registered")
  }

  private func refreshCurrentState() async throws {
    let stateData = try await performRequest(.currentState)
    guard let stateData else {
      throw FanCurveAgentClientError.invalidReply
    }
    let state: RuntimeState
    do {
      state = try JSONDecoder().decode(RuntimeState.self, from: stateData)
    } catch {
      fanCurveAgentClientLog.error(
        "agent_client.current_state.decode_failed error=\(error.localizedDescription, privacy: .public) recovery=propagate"
      )
      throw error
    }
    apply(runtimeState: state)
  }

  func send(_ command: AgentCommand) async throws {
    control.recordCommand(command)
    let commandData = try commandTransport.encode(command)
    let responseData = try await performRequest(
      .command(commandData, name: command.logName)
    )
    guard let responseData else {
      throw FanCurveAgentClientError.invalidReply
    }
    let response = try commandTransport.decode(responseData)
    try commandTransport.accept(response, for: command)
  }

  func performRequest(_ request: AgentXPCRequest) async throws -> Data? {
    let requestID = UUID()
    let resumer = AgentXPCReplyResumer(operation: request.operation)
    pendingRequests[requestID] = resumer
    defer {
      pendingRequests.removeValue(forKey: requestID)
    }
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        resumer.install(continuation)
        requestDispatcher.dispatch { [self] in
          guard resumer.claimDispatch() else {
            return
          }
          guard let proxy = remoteProxy(resumer: resumer) else {
            return
          }
          start(request, using: proxy, resumer: resumer)
        }
      }
    } onCancel: {
      resumer.cancel()
    }
  }

  private func start(
    _ request: AgentXPCRequest,
    using proxy: FanCurveAgentXPCProtocol,
    resumer: AgentXPCReplyResumer
  ) {
    switch request {
    case .registerEvents:
      proxy.registerForEvents { success, errorMessage in
        resumer.resume(success: success, errorMessage: errorMessage)
      }
    case .currentState:
      proxy.getCurrentState { success, data, errorMessage in
        Self.resumeDataReply(
          resumer,
          success: success,
          data: data,
          errorMessage: errorMessage
        )
      }
    case .command(let commandData, _):
      let transport = commandTransport
      proxy.sendCommand(commandData) { success, responseData, errorMessage in
        transport.resume(
          resumer,
          success: success,
          responseData: responseData,
          errorMessage: errorMessage
        )
      }
    case .ownership:
      proxy.getOwnership { success, data, errorMessage in
        Self.resumeDataReply(
          resumer,
          success: success,
          data: data,
          errorMessage: errorMessage
        )
      }
    }
  }

  nonisolated private static func resumeDataReply(
    _ resumer: AgentXPCReplyResumer,
    success: Bool,
    data: Data?,
    errorMessage: String?
  ) {
    if let errorMessage, !success {
      resumer.resume(
        throwing: FanCurveAgentClientError.commandRejected(errorMessage))
      return
    }
    guard success, let data else {
      resumer.resume(throwing: FanCurveAgentClientError.invalidReply)
      return
    }
    resumer.resume(returning: data)
  }

  private func remoteProxy(
    resumer: AgentXPCReplyResumer
  ) -> FanCurveAgentXPCProtocol? {
    guard let connection else {
      resumer.resume(throwing: FanCurveAgentClientError.connectionUnavailable)
      return nil
    }
    let generation = connectionGeneration
    let connectionID = ObjectIdentifier(connection)
    let errorHandler: @Sendable (Error) -> Void = { [weak self] error in
      resumer.resume(throwing: error)
      self?.handleRemoteProxyFailure(
        error,
        connectionID: connectionID,
        generation: generation
      )
    }
    guard
      let proxy = remoteProxyProvider.remoteProxy(
        for: connection,
        errorHandler: errorHandler
      )
    else {
      resumer.resume(throwing: FanCurveAgentClientError.missingRemoteProxy)
      return nil
    }
    return proxy
  }

  nonisolated private func handleRemoteProxyFailure(
    _ error: Error,
    connectionID failedConnectionID: ObjectIdentifier,
    generation failedGeneration: UInt64
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard
        connectionGeneration == failedGeneration,
        connection.map(ObjectIdentifier.init) == failedConnectionID
      else {
        fanCurveAgentClientLog.notice(
          "agent_client.proxy.stale_error_suppressed failed_generation=\(failedGeneration, privacy: .public) current_generation=\(connectionGeneration, privacy: .public) recovery=preserve-current-connection"
        )
        return
      }
      cancelPendingRequests(reason: "remote-proxy-failure", error: error)
      let activeConnection = connection
      connection = nil
      activeConnection?.invalidate()
      lastError = error.localizedDescription
      connectionState = .failed(error.localizedDescription)
      fanCurveAgentClientLog.notice(
        "agent_client.proxy.failed error=\(error.localizedDescription, privacy: .public) recovery=schedule-reconnect"
      )
      scheduleReconnect()
    }
  }

  private func apply(runtimeState state: RuntimeState) {
    runtimeState = state
    snapshot = state.snapshot
    connectionState = .connected
    lastError = nil
    fanCurveAgentClientLog.debug("agent_client.state.updated")
  }

  private func handleDisconnect(_ disconnectedGeneration: UInt64, reason: String) {
    guard connectionGeneration == disconnectedGeneration, connection != nil else {
      return
    }
    cancelPendingRequests(
      reason: reason,
      error: FanCurveAgentClientError.connectionUnavailable
    )
    connection = nil
    connectionState = .disconnected
    control.recordEvent(.disconnected)
    fanCurveAgentClientLog.notice(
      "agent_client.connection.disconnected reason=\(reason, privacy: .public) recovery=schedule-reconnect"
    )
    scheduleReconnect()
  }

  private func scheduleReconnect() {
    guard !stopped, reconnectTask == nil else { return }
    control.recordEvent(.reconnectScheduled)
    let delay = reconnectDelay
    reconnectTask = Task { @MainActor [weak self] in
      let clock = ContinuousClock()
      do {
        try await clock.sleep(for: .seconds(delay))
      } catch {
        fanCurveAgentClientLog.notice(
          "agent_client.reconnect.cancelled recovery=skip-reconnect"
        )
        return
      }
      guard let self else { return }
      reconnectTask = nil
      guard !stopped, connection == nil else { return }
      connect()
    }
  }

  private func connectionIsAllowed() -> Bool {
    switch control.connectionGate() {
    case .allowed:
      return true
    case .refused(let reason):
      control.recordEvent(.connectionAttemptGated)
      connectionState = .failed(reason)
      lastError = reason
      fanCurveAgentClientLog.notice(
        "agent_client.connection.gated reason=\(reason, privacy: .public) recovery=wait-for-explicit-retry"
      )
      return false
    }
  }

  private func cancelPendingRequests(
    reason: String,
    error: Error = CancellationError()
  ) {
    let requests = Array(pendingRequests.values)
    pendingRequests.removeAll()
    guard !requests.isEmpty else {
      return
    }
    fanCurveAgentClientLog.notice(
      "agent_client.requests.cancelling count=\(requests.count, privacy: .public) reason=\(reason, privacy: .public) recovery=resume-continuations"
    )
    for request in requests {
      if error is CancellationError {
        request.cancel()
      } else {
        request.resume(throwing: error)
      }
    }
  }
}
