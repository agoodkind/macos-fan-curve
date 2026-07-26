//
//  FanCurveAgentClient.swift
//  FanCurve
//
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Combine
import Foundation

private let fanCurveAgentClientLog = AppLog.make(category: "FanCurveAgentClient")

private enum FanCurveAgentClientConstants {
  static let snapshotFreshnessWindow: TimeInterval = 5
}

private final class AgentVoidReplyResumer: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Error>?

  init(_ continuation: CheckedContinuation<Void, Error>) {
    self.continuation = continuation
  }

  func resume(success: Bool, errorMessage: String?) {
    if success {
      resume()
      return
    }
    resume(
      throwing: FanCurveAgentClientError.commandRejected(errorMessage ?? "Command rejected")
    )
  }

  func resume() {
    lock.lock()
    defer { lock.unlock() }
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume()
  }

  func resume(throwing error: Error) {
    lock.lock()
    defer { lock.unlock() }
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(throwing: error)
  }
}

enum FanCurveAgentConnectionState: Sendable, Equatable {
  case connected
  case connecting
  case disconnected
  case failed(String)
}

enum FanCurveAgentClientError: LocalizedError {
  case commandRejected(String)
  case connectionUnavailable
  case invalidReply
  case missingRemoteProxy

  var errorDescription: String? {
    switch self {
    case .commandRejected(let message):
      return message
    case .connectionUnavailable:
      return "FanCurveAgent XPC connection is unavailable"
    case .invalidReply:
      return "FanCurveAgent returned an invalid reply"
    case .missingRemoteProxy:
      return "FanCurveAgent remote proxy is unavailable"
    }
  }
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
  private let commandTransport = AgentCommandTransport()
  private let decoder = JSONDecoder()
  private var stopped = false
  private var connectionGeneration: UInt64 = 0

  init(
    serviceName: String = FanCurveAgentXPC.serviceName,
    connectionFactory: (@MainActor () -> NSXPCConnection)? = nil,
    control: any FanCurveAgentClientControlling =
      ProductionAgentClientControl(),
    reconnectDelay: TimeInterval = 1
  ) {
    self.serviceName = serviceName
    self.connectionFactory =
      connectionFactory ?? {
        NSXPCConnection(machServiceName: serviceName, options: [])
      }
    self.control = control
    self.reconnectDelay = reconnectDelay
    super.init()
  }

  func start() {
    guard connection == nil else { return }
    stopped = false
    switch control.connectionGate() {
    case .allowed:
      connect()
    case .refused(let reason):
      control.recordEvent(.connectionAttemptGated)
      connectionState = .failed(reason)
      lastError = reason
      fanCurveAgentClientLog.notice(
        "agent_client.connection.gated reason=\(reason, privacy: .public) recovery=wait-for-explicit-retry"
      )
    }
  }

  func stop() {
    stopped = true
    connectionTask?.cancel()
    connectionTask = nil
    reconnectTask?.cancel()
    reconnectTask = nil
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

  private func registerForEvents() async throws {
    try await withCheckedThrowingContinuation { continuation in
      let resumer = AgentVoidReplyResumer(continuation)
      guard let proxy = remoteProxy(resumer: resumer) else { return }
      proxy.registerForEvents { success, errorMessage in
        resumer.resume(success: success, errorMessage: errorMessage)
      }
    }
    fanCurveAgentClientLog.debug("agent_client.events.registered")
  }

  private func refreshCurrentState() async throws {
    let proxy = try remoteProxy()
    let state: RuntimeState = try await withCheckedThrowingContinuation { continuation in
      proxy.getCurrentState { success, data, errorMessage in
        if let errorMessage, !success {
          continuation.resume(
            throwing: FanCurveAgentClientError.commandRejected(errorMessage))
          return
        }
        guard success, let data else {
          continuation.resume(throwing: FanCurveAgentClientError.invalidReply)
          return
        }
        do {
          let state = try JSONDecoder().decode(RuntimeState.self, from: data)
          continuation.resume(returning: state)
        } catch {
          fanCurveAgentClientLog.error(
            "agent_client.current_state.decode_failed error=\(error.localizedDescription, privacy: .public) recovery=propagate"
          )
          continuation.resume(throwing: error)
        }
      }
    }
    apply(runtimeState: state)
  }

  private func send(_ command: AgentCommand) async throws {
    control.recordCommand(command)
    let proxy = try remoteProxy()
    try await commandTransport.send(command, to: proxy)
  }

  private func remoteProxy() throws -> FanCurveAgentXPCProtocol {
    guard let connection else { throw FanCurveAgentClientError.connectionUnavailable }
    guard
      let proxy = connection.remoteObjectProxyWithErrorHandler(
        Self.makeRemoteProxyErrorHandler(client: self)
      ) as? FanCurveAgentXPCProtocol
    else {
      throw FanCurveAgentClientError.missingRemoteProxy
    }
    return proxy
  }

  private func remoteProxy(resumer: AgentVoidReplyResumer) -> FanCurveAgentXPCProtocol? {
    guard let connection else {
      resumer.resume(throwing: FanCurveAgentClientError.connectionUnavailable)
      return nil
    }
    let errorHandler: @Sendable (Error) -> Void = { [weak self] error in
      resumer.resume(throwing: error)
      self?.handleRemoteProxyFailure(error)
    }
    guard
      let proxy = connection.remoteObjectProxyWithErrorHandler(errorHandler)
        as? FanCurveAgentXPCProtocol
    else {
      resumer.resume(throwing: FanCurveAgentClientError.missingRemoteProxy)
      return nil
    }
    return proxy
  }

  nonisolated private static func makeRemoteProxyErrorHandler(
    client: FanCurveAgentClient
  ) -> @Sendable (Error) -> Void {
    { [weak client] error in
      client?.handleRemoteProxyFailure(error)
    }
  }

  nonisolated private func handleRemoteProxyFailure(_ error: Error) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
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
}

// MARK: - Commands

extension FanCurveAgentClient {
  func setFanControlEnabled(_ enabled: Bool) async throws {
    try await send(.setFanControlEnabled(enabled))
  }

  func setBoostEnabled(_ enabled: Bool) async throws {
    try await send(.setBoostEnabled(enabled))
  }

  func setCurve(points: [CurvePoint], interpolationMode: InterpolationMode) async throws {
    let update = AgentCurveUpdate(points: points, interpolationMode: interpolationMode)
    try await send(.setCurve(update))
  }

  func setApplyInBackground(_ enabled: Bool) async throws {
    try await send(.setApplyInBackground(enabled))
  }

  func installOrRepairHelper() async throws {
    try await send(.installOrRepairHelper)
  }

  func openSystemSettings() async throws {
    try await send(.openSystemSettings)
  }

  func setFanRPM(_ fanIndex: UInt, rpm: Float) async throws {
    let request = AgentFanRPMRequest(fanIndex: fanIndex, rpm: rpm)
    try await send(.requestFanRPM(request))
  }

  func setFanAuto(_ fanIndex: UInt) async throws {
    try await send(.requestFanAuto(fanIndex: fanIndex))
  }

  func getOwnership() async throws -> [AgentOwnershipEntry] {
    let proxy = try remoteProxy()
    return try await withCheckedThrowingContinuation { continuation in
      proxy.getOwnership { success, data, errorMessage in
        if let errorMessage, !success {
          continuation.resume(
            throwing: FanCurveAgentClientError.commandRejected(errorMessage))
          return
        }
        guard success, let data else {
          continuation.resume(throwing: FanCurveAgentClientError.invalidReply)
          return
        }
        do {
          let rows = try JSONDecoder().decode([AgentOwnershipEntry].self, from: data)
          continuation.resume(returning: rows)
        } catch {
          fanCurveAgentClientLog.error(
            "agent_client.ownership.decode_failed error=\(error.localizedDescription, privacy: .public) recovery=propagate"
          )
          continuation.resume(throwing: error)
        }
      }
    }
  }
}

// MARK: - Runtime properties

extension FanCurveAgentClient {
  var isFresh: Bool {
    guard let snapshot else { return false }
    return Date().timeIntervalSince(snapshot.timestamp)
      < FanCurveAgentClientConstants.snapshotFreshnessWindow
  }

  var governingTemperature: Double { snapshot?.governingTemperatureC ?? 0 }
  var committedTemperature: Double { snapshot?.committedTemperatureC ?? 0 }
  var rawPressureTemperature: Double? { snapshot?.rawPressureTemperatureC }
  var fans: [AgentFanSnapshot] { snapshot?.fans ?? [] }
  var cpuLoadPercent: Double { snapshot?.cpuLoadPercent ?? 0 }
  var gpuLoadPercent: Double { snapshot?.gpuLoadPercent ?? 0 }
  var baseCurvePercent: Double { snapshot?.baseCurvePercent ?? 0 }
  var rawBaselinePercent: Double { snapshot?.rawBaselinePercent ?? 0 }
  var semanticDemandPercent: Double? { snapshot?.semanticDemandPercent }
  var semanticDemandTemperature: Double? { snapshot?.semanticDemandTemperatureC }
  var commandedTargetPercent: Double {
    snapshot?.commandedTargetPercent ?? snapshot?.committedPercent ?? 0
  }
  var assistFloorPercent: Double? { snapshot?.assistFloorPercent }
  var activeAssistKinds: [LoadAssistKind] { snapshot?.activeAssistKinds ?? [] }
  var helperReachable: Bool { snapshot?.helperReachable ?? false }
  var boostEnabled: Bool { snapshot?.boostEnabled ?? false }
  var curveActive: Bool { snapshot?.curveActive ?? false }
}
