//
//  FanCurveAgentClient.swift
//  FanCurve
//
//  Copyright © 2026
//

import AppLog
import Combine
import Foundation

private let fanCurveAgentClientLog = AppLog.make(category: "FanCurveAgentClient")

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
        guard connection == nil else { return }
        connect()
    }

    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.invalidate()
        connection = nil
        connectionState = .disconnected
        fanCurveAgentClientLog.info("agent_client.stopped")
    }

    func requestRefresh() async throws {
        let proxy = try remoteProxy()
        try await withCheckedThrowingContinuation { continuation in
            proxy.requestRefresh { success, errorMessage in
                Self.resumeBooleanReply(
                    continuation,
                    success: success,
                    errorMessage: errorMessage
                )
            }
        }
        fanCurveAgentClientLog.debug("agent_client.refresh.requested")
    }

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

    func registerHelperDaemon() async throws {
        try await send(.registerHelperDaemon)
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
                    continuation.resume(throwing: FanCurveAgentClientError.commandRejected(errorMessage))
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

    var isFresh: Bool {
        guard let snapshot else { return false }
        return Date().timeIntervalSince(snapshot.timestamp) < 5
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
    var commandedTargetPercent: Double { snapshot?.commandedTargetPercent ?? snapshot?.committedPercent ?? 0 }
    var committedPercent: Double { snapshot?.committedPercent ?? 0 }
    var controllerMode: AgentControllerMode { snapshot?.controllerMode ?? .holding }
    var holdRemainingSeconds: Double { snapshot?.holdRemainingSeconds ?? 0 }
    var assistFloorPercent: Double? { snapshot?.assistFloorPercent }
    var activeAssistKinds: [LoadAssistKind] { snapshot?.activeAssistKinds ?? [] }
    var helperReachable: Bool { snapshot?.helperReachable ?? false }
    var boostEnabled: Bool { snapshot?.boostEnabled ?? false }
    var curveActive: Bool { snapshot?.curveActive ?? false }

    private func connect() {
        connectionState = .connecting
        let nextConnection = NSXPCConnection(machServiceName: serviceName, options: [])
        nextConnection.remoteObjectInterface = NSXPCInterface(with: FanCurveAgentXPCProtocol.self)
        nextConnection.exportedInterface = NSXPCInterface(with: FanCurveAgentXPCEventProtocol.self)
        nextConnection.exportedObject = self
        nextConnection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.handleDisconnect(reason: "interrupted")
            }
        }
        nextConnection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.handleDisconnect(reason: "invalidated")
            }
        }
        connection = nextConnection
        nextConnection.resume()
        fanCurveAgentClientLog.notice("agent_client.connection.started service=\(serviceName, privacy: .public)")
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
        let proxy = try remoteProxy()
        try await withCheckedThrowingContinuation { continuation in
            proxy.registerForEvents { success, errorMessage in
                Self.resumeBooleanReply(
                    continuation,
                    success: success,
                    errorMessage: errorMessage
                )
            }
        }
        fanCurveAgentClientLog.debug("agent_client.events.registered")
    }

    private func refreshCurrentState() async throws {
        let proxy = try remoteProxy()
        let state: RuntimeState = try await withCheckedThrowingContinuation { continuation in
            proxy.getCurrentState { success, data, errorMessage in
                if let errorMessage, !success {
                    continuation.resume(throwing: FanCurveAgentClientError.commandRejected(errorMessage))
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
        let proxy = try remoteProxy()
        let data = try encoder.encode(command)
        let response: AgentCommandResponse = try await withCheckedThrowingContinuation { continuation in
            proxy.sendCommand(data) { success, responseData, errorMessage in
                if let errorMessage, !success {
                    continuation.resume(throwing: FanCurveAgentClientError.commandRejected(errorMessage))
                    return
                }
                guard success, let responseData else {
                    continuation.resume(throwing: FanCurveAgentClientError.invalidReply)
                    return
                }
                do {
                    let response = try JSONDecoder().decode(AgentCommandResponse.self, from: responseData)
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
        fanCurveAgentClientLog.info("agent_client.command.sent kind=\(command.logName, privacy: .public)")
    }

    private func remoteProxy() throws -> FanCurveAgentXPCProtocol {
        guard let connection else { throw FanCurveAgentClientError.connectionUnavailable }
        guard
            let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
                Task { @MainActor in
                    self?.lastError = error.localizedDescription
                    self?.connectionState = .failed(error.localizedDescription)
                    fanCurveAgentClientLog.notice(
                        "agent_client.proxy.failed error=\(error.localizedDescription, privacy: .public) recovery=schedule-reconnect"
                    )
                    self?.scheduleReconnect()
                }
            }) as? FanCurveAgentXPCProtocol
        else {
            throw FanCurveAgentClientError.missingRemoteProxy
        }
        return proxy
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
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                fanCurveAgentClientLog.debug(
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

    nonisolated private static func resumeBooleanReply(
        _ continuation: CheckedContinuation<Void, Error>,
        success: Bool,
        errorMessage: String?
    ) {
        if success {
            continuation.resume()
            return
        }
        continuation.resume(
            throwing: FanCurveAgentClientError.commandRejected(errorMessage ?? "Command rejected")
        )
    }
}
