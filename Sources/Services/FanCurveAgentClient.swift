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
  private var reconnectTask: Task<Void, Never>?
  private let serviceName: String
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(serviceName: String = FanCurveAgentXPC.serviceName) {
    self.serviceName = serviceName
    super.init()
  }

  func start() {
    #if DEBUG
      if devScenarioCancellable == nil {
        let store = DevScenarioStore.shared
        devScenarioCancellable = store.$current.sink { [weak self] scenario in
          Task { @MainActor [weak self] in
            self?.applyDevScenario(scenario)
          }
        }
        return
      }
    #endif
    guard connection == nil else { return }
    connect()
  }

  #if DEBUG
    var devScenarioCancellable: AnyCancellable?
    var devTimer: Timer?
    var devScenario: DevScenario?
    var devStartDate = Date()
    var devBoostOverride: DevToggleOverride = .inherit
    var devCurveOverride: DevToggleOverride = .inherit
  #endif

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

  nonisolated func agentRuntimeStateDidUpdate(_ stateData: Data) {
    Task { @MainActor in
      do {
        let state = try decoder.decode(RuntimeState.self, from: stateData)
        apply(runtimeState: state)
      } catch {
        lastError = error.localizedDescription
        fanCurveAgentClientLog.error(
          "agent_client.state.decode_failed error=\(error.localizedDescription, privacy: .public) recovery=keep-last-state"
        )
      }
    }
  }

  private func connect() {
    connectionState = .connecting
    let nextConnection = NSXPCConnection(machServiceName: serviceName, options: [])
    nextConnection.remoteObjectInterface = NSXPCInterface(with: FanCurveAgentXPCProtocol.self)
    nextConnection.exportedInterface = NSXPCInterface(with: FanCurveAgentXPCEventProtocol.self)
    nextConnection.exportedObject = self
    nextConnection.interruptionHandler = { @Sendable [weak self] in
      Task { @MainActor in
        self?.handleDisconnect(reason: "interrupted")
      }
    }
    nextConnection.invalidationHandler = { @Sendable [weak self] in
      Task { @MainActor in
        self?.handleDisconnect(reason: "invalidated")
      }
    }
    connection = nextConnection
    nextConnection.resume()
    fanCurveAgentClientLog.notice(
      "agent_client.connection.started service=\(serviceName, privacy: .public)")
    Task {
      do {
        try await registerForEvents()
        try await refreshCurrentState()
        connectionState = .connected
        lastError = nil
        fanCurveAgentClientLog.notice("agent_client.connection.ready")
      } catch {
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
    #if DEBUG
      if isDevSimulating {
        applyDevCommand(command)
        return
      }
    #endif
    let proxy = try remoteProxy()
    let data = try encoder.encode(command)
    let response: AgentCommandResponse =
      try await withCheckedThrowingContinuation { continuation in
        proxy.sendCommand(data) { success, responseData, errorMessage in
          if let errorMessage, !success {
            continuation.resume(
              throwing: FanCurveAgentClientError.commandRejected(errorMessage))
            return
          }
          guard success, let responseData else {
            continuation.resume(throwing: FanCurveAgentClientError.invalidReply)
            return
          }
          do {
            let response = try JSONDecoder().decode(
              AgentCommandResponse.self, from: responseData)
            continuation.resume(returning: response)
          } catch {
            fanCurveAgentClientLog.error(
              "agent_client.command.response_decode_failed error=\(error.localizedDescription, privacy: .public) recovery=propagate"
            )
            continuation.resume(throwing: error)
          }
        }
      }
    guard response.accepted else {
      throw FanCurveAgentClientError.commandRejected(response.message ?? "Command rejected")
    }
    fanCurveAgentClientLog.info(
      "agent_client.command.sent kind=\(command.logName, privacy: .public)")
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
    Task { @MainActor [weak self] in
      self?.lastError = error.localizedDescription
      self?.connectionState = .failed(error.localizedDescription)
      fanCurveAgentClientLog.notice(
        "agent_client.proxy.failed error=\(error.localizedDescription, privacy: .public) recovery=schedule-reconnect"
      )
      self?.scheduleReconnect()
    }
  }

  private func apply(runtimeState state: RuntimeState) {
    runtimeState = state
    snapshot = state.snapshot
    connectionState = .connected
    lastError = nil
    fanCurveAgentClientLog.debug("agent_client.state.updated")
  }

  private func handleDisconnect(reason: String) {
    connection = nil
    connectionState = .disconnected
    fanCurveAgentClientLog.notice(
      "agent_client.connection.disconnected reason=\(reason, privacy: .public) recovery=schedule-reconnect"
    )
    scheduleReconnect()
  }

  private func scheduleReconnect() {
    guard reconnectTask == nil else { return }
    reconnectTask = Task { [weak self] in
      let clock = ContinuousClock()
      do {
        try await clock.sleep(for: .seconds(1))
      } catch {
        fanCurveAgentClientLog.notice(
          "agent_client.reconnect.cancelled recovery=skip-reconnect"
        )
        return
      }
      await MainActor.run {
        guard let self else { return }
        self.reconnectTask = nil
        guard self.connection == nil else { return }
        self.connect()
      }
    }
  }
}

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

#if DEBUG

  extension FanCurveAgentClient {
    var isDevSimulating: Bool { devScenario != nil }

    /// Drives every published value from a forced scenario and stops talking to
    /// the real XPC endpoint. Passing `nil` clears the scenario and reconnects.
    func applyDevScenario(_ scenario: DevScenario?) {
      devTimer?.invalidate()
      devTimer = nil
      devBoostOverride = .inherit
      devCurveOverride = .inherit
      devScenario = scenario

      guard let scenario else {
        fanCurveAgentClientLog.notice(
          "agent_client.dev.scenario.cleared recovery=reconnect")
        connectionState = .disconnected
        connect()
        return
      }

      connection?.interruptionHandler = nil
      connection?.invalidationHandler = nil
      connection?.invalidate()
      connection = nil
      reconnectTask?.cancel()
      reconnectTask = nil
      devStartDate = Date()
      fanCurveAgentClientLog.notice(
        "agent_client.dev.scenario.applied scenario=\(scenario.rawValue, privacy: .public)")
      publishDevScenario()

      guard scenario.animates else { return }
      devTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.publishDevScenario()
        }
      }
    }

    func applyDevCommand(_ command: AgentCommand) {
      switch command {
      case .setBoostEnabled(let enabled):
        devBoostOverride = enabled ? .on : .off
      case .setFanControlEnabled(let enabled):
        devCurveOverride = enabled ? .on : .off
      case .setCurve, .setApplyInBackground, .requestFanRPM, .requestFanAuto,
        .openSystemSettings:
        break
      }
      fanCurveAgentClientLog.notice(
        "agent_client.dev.command kind=\(command.logName, privacy: .public)")
      publishDevScenario()
    }

    private func publishDevScenario() {
      guard let scenario = devScenario else { return }
      let now = Date()
      let phase = now.timeIntervalSince(devStartDate)
      let curveActive = devCurveOverride.value(default: scenario.naturalCurveActive)
      let boostEnabled = devBoostOverride.value(default: scenario.naturalBoostEnabled)
      runtimeState = scenario.runtimeState(
        now: now, phase: phase, curveActive: curveActive, boostEnabled: boostEnabled)
      snapshot = scenario.snapshot(
        now: now, phase: phase, curveActive: curveActive, boostEnabled: boostEnabled)
      connectionState = scenario.connectionState
      lastError = nil
    }
  }

#endif
