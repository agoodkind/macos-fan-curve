//
//  FanCurveAgentXPCService.swift
//  FanCurveAgent
//
//  Copyright © 2026
//

import AppLog
import Foundation
import ServiceManagement

private let agentXPCLog = AppLog.make(category: "FanCurveAgentXPC")

final class FanCurveAgentXPCService: NSObject, NSXPCListenerDelegate, FanCurveAgentXPCProtocol, @unchecked Sendable {
    private let controller: AgentController
    private let listener: NSXPCListener
    private let callbackLock = NSLock()
    private var eventCallbacks: [FanCurveAgentXPCEventProtocol] = []

    init(
        controller: AgentController,
        serviceName: String = FanCurveAgentXPC.serviceName
    ) {
        self.controller = controller
        self.listener = NSXPCListener(machServiceName: serviceName)
        super.init()
        self.listener.delegate = self
        self.controller.runtimeStateDidChange = { [weak self] runtimeState in
            self?.publishRuntimeState(runtimeState)
        }
    }

    func start() {
        agentXPCLog.notice(
            "agent.xpc.starting service=\(FanCurveAgentXPC.serviceName, privacy: .public)"
        )
        listener.resume()
        agentXPCLog.notice("agent.xpc.started")
    }

    func stop() {
        agentXPCLog.notice("agent.xpc.stopping")
        listener.invalidate()
        agentXPCLog.notice("agent.xpc.stopped")
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        agentXPCLog.info("agent.xpc.connection.accepting")
        connection.exportedInterface = NSXPCInterface(with: FanCurveAgentXPCProtocol.self)
        connection.exportedObject = self
        connection.remoteObjectInterface = NSXPCInterface(with: FanCurveAgentXPCEventProtocol.self)
        connection.invalidationHandler = {
            agentXPCLog.info("agent.xpc.connection.invalidated")
            self.clearEventCallbacks(reason: "connection-invalidated")
        }
        connection.interruptionHandler = {
            agentXPCLog.info("agent.xpc.connection.interrupted")
            self.clearEventCallbacks(reason: "connection-interrupted")
        }
        connection.resume()
        agentXPCLog.info("agent.xpc.connection.accepted")
        return true
    }

    func getCurrentState(reply: @escaping @Sendable (Bool, Data?, String?) -> Void) {
        agentXPCLog.debug("agent.xpc.current_state.requested")
        let runtimeState = controller.currentRuntimeStateForXPC()

        do {
            let data = try JSONEncoder().encode(runtimeState)
            agentXPCLog.debug("agent.xpc.current_state.returned")
            reply(true, data, nil)
        } catch {
            agentXPCLog.error(
                "agent.xpc.current_state.encode_failed error=\(error.localizedDescription, privacy: .public) recovery=return-error"
            )
            reply(false, nil, error.localizedDescription)
        }
    }

    func registerForEvents(reply: @escaping @Sendable (Bool, String?) -> Void) {
        guard
            let currentConnection = NSXPCConnection.current(),
            let callback = currentConnection.remoteObjectProxy as? FanCurveAgentXPCEventProtocol
        else {
            agentXPCLog.error("agent.xpc.events.register_failed reason=missing-remote-proxy")
            reply(false, "Missing app event callback")
            return
        }

        callbackLock.lock()
        eventCallbacks = [callback]
        callbackLock.unlock()
        agentXPCLog.info("agent.xpc.events.registered")
        publishRuntimeState(controller.currentRuntimeStateForXPC())
        reply(true, nil)
    }

    func requestRefresh(reply: @escaping @Sendable (Bool, String?) -> Void) {
        agentXPCLog.info("agent.xpc.refresh.requested")
        controller.requestTick()
        reply(true, nil)
    }

    func sendCommand(
        _ commandData: Data,
        reply: @escaping @Sendable (Bool, Data?, String?) -> Void
    ) {
        do {
            let command = try JSONDecoder().decode(AgentCommand.self, from: commandData)
            agentXPCLog.info("agent.xpc.command.received kind=\(command.logName, privacy: .public)")
            Task {
                let response = await self.handleCommand(command)
                do {
                    let data = try JSONEncoder().encode(response)
                    reply(response.accepted, data, response.message)
                } catch {
                    agentXPCLog.error(
                        "agent.xpc.command.response_encode_failed error=\(error.localizedDescription, privacy: .public) recovery=return-error"
                    )
                    reply(false, nil, error.localizedDescription)
                }
            }
        } catch {
            agentXPCLog.error(
                "agent.xpc.command.decode_failed error=\(error.localizedDescription, privacy: .public) recovery=return-error"
            )
            reply(false, nil, error.localizedDescription)
        }
    }

    func getOwnership(reply: @escaping @Sendable (Bool, Data?, String?) -> Void) {
        agentXPCLog.debug("agent.xpc.ownership.requested")
        Task {
            do {
                let rows = try await controller.xpcClient.getOwnership()
                let data = try JSONEncoder().encode(rows)
                agentXPCLog.debug("agent.xpc.ownership.returned count=\(rows.count, privacy: .public)")
                reply(true, data, nil)
            } catch {
                agentXPCLog.notice(
                    "agent.xpc.ownership.failed error=\(error.localizedDescription, privacy: .public) recovery=return-error"
                )
                reply(false, nil, error.localizedDescription)
            }
        }
    }

    func setFanControlEnabled(
        _ enabled: Bool,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        agentXPCLog.info(
            "agent.xpc.fan_control.set requested=\(enabled, privacy: .public)"
        )
        controller.sharedConfig.defaults.set(enabled, forKey: SharedConfigKeys.curveActive)
        publishConfigChange()
        reply(true, nil)
    }

    func setBoostEnabled(
        _ enabled: Bool,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        agentXPCLog.info("agent.xpc.boost.set requested=\(enabled, privacy: .public)")
        controller.sharedConfig.defaults.set(enabled, forKey: SharedConfigKeys.boostEnabled)
        publishConfigChange()
        reply(true, nil)
    }

    func setCurve(
        _ curveData: Data,
        reply: @escaping @Sendable (Bool, String?) -> Void
    ) {
        agentXPCLog.info("agent.xpc.curve.set bytes=\(curveData.count, privacy: .public)")
        controller.sharedConfig.defaults.set(curveData, forKey: SharedConfigKeys.curvePoints)
        publishConfigChange()
        reply(true, nil)
    }

    private func publishConfigChange() {
        controller.sharedConfig.defaults.synchronize()
        controller.requestTick()
    }

    private func handleCommand(_ command: AgentCommand) async -> AgentCommandResponse {
        switch command {
        case .openSystemSettings:
            if #available(macOS 13.0, *) {
                SMAppService.openSystemSettingsLoginItems()
                agentXPCLog.notice("agent.xpc.command.system_settings.opened")
                return AgentCommandResponse(accepted: true, message: nil)
            }
            return AgentCommandResponse(accepted: false, message: "System Settings action requires macOS 13")
        case .registerHelperDaemon:
            return await registerHelperDaemon()
        case .requestFanAuto(let fanIndex):
            do {
                try await controller.xpcClient.setFanAuto(fanIndex)
                controller.requestTick()
                return AgentCommandResponse(accepted: true, message: nil)
            } catch {
                agentXPCLog.notice(
                    "agent.xpc.command.fan_auto_failed fan=\(fanIndex, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error"
                )
                return AgentCommandResponse(accepted: false, message: error.localizedDescription)
            }
        case .requestFanRPM(let fanIndex, let rpm):
            do {
                try await controller.xpcClient.setFanRPM(fanIndex, rpm: rpm)
                controller.requestTick()
                return AgentCommandResponse(accepted: true, message: nil)
            } catch {
                agentXPCLog.notice(
                    "agent.xpc.command.fan_rpm_failed fan=\(fanIndex, privacy: .public) rpm=\(rpm, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error"
                )
                return AgentCommandResponse(accepted: false, message: error.localizedDescription)
            }
        case .setApplyInBackground(let enabled):
            controller.sharedConfig.defaults.set(enabled, forKey: SharedConfigKeys.applyInBackground)
            publishConfigChange()
            return AgentCommandResponse(accepted: true, message: nil)
        case .setBoostEnabled(let enabled):
            controller.sharedConfig.defaults.set(enabled, forKey: SharedConfigKeys.boostEnabled)
            publishConfigChange()
            return AgentCommandResponse(accepted: true, message: nil)
        case .setCurve(let points, let interpolationMode):
            do {
                let data = try JSONEncoder().encode(CurveColumns.normalize(points))
                controller.sharedConfig.defaults.set(data, forKey: SharedConfigKeys.curvePoints)
                controller.sharedConfig.defaults.set(
                    interpolationMode.rawValue,
                    forKey: SharedConfigKeys.interpolationMode
                )
                publishConfigChange()
                return AgentCommandResponse(accepted: true, message: nil)
            } catch {
                agentXPCLog.error(
                    "agent.xpc.command.curve_encode_failed point_count=\(points.count, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error"
                )
                return AgentCommandResponse(accepted: false, message: error.localizedDescription)
            }
        case .setFanControlEnabled(let enabled):
            controller.sharedConfig.defaults.set(enabled, forKey: SharedConfigKeys.curveActive)
            publishConfigChange()
            return AgentCommandResponse(accepted: true, message: nil)
        }
    }

    private func registerHelperDaemon() async -> AgentCommandResponse {
        guard #available(macOS 13.0, *) else {
            return AgentCommandResponse(accepted: false, message: "Helper setup requires macOS 13")
        }
        return await Task.detached {
            let service = SMAppService.daemon(plistName: generatedHelperDaemonPlistName)
            do {
                try service.register()
                agentXPCLog.notice(
                    "agent.xpc.command.helper_register.done status=\(service.status.rawValue, privacy: .public)"
                )
                return AgentCommandResponse(accepted: true, message: nil)
            } catch {
                agentXPCLog.error(
                    "agent.xpc.command.helper_register.failed error=\(error.localizedDescription, privacy: .public) recovery=return-error"
                )
                return AgentCommandResponse(accepted: false, message: error.localizedDescription)
            }
        }.value
    }

    private func publishRuntimeState(_ runtimeState: RuntimeState) {
        let callbacks = currentEventCallbacks()
        guard !callbacks.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(runtimeState)
            for callback in callbacks {
                callback.agentRuntimeStateDidUpdate(data)
            }
            agentXPCLog.debug("agent.xpc.events.runtime_state.sent callbacks=\(callbacks.count, privacy: .public)")
        } catch {
            agentXPCLog.error(
                "agent.xpc.events.runtime_state.encode_failed error=\(error.localizedDescription, privacy: .public) recovery=drop-event"
            )
        }
    }

    private func currentEventCallbacks() -> [FanCurveAgentXPCEventProtocol] {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        return eventCallbacks
    }

    private func clearEventCallbacks(reason: String) {
        callbackLock.lock()
        eventCallbacks.removeAll()
        callbackLock.unlock()
        agentXPCLog.info("agent.xpc.events.cleared reason=\(reason, privacy: .public)")
    }
}
