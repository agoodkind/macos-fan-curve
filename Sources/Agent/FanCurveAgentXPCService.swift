//
//  FanCurveAgentXPCService.swift
//  FanCurveAgent
//
//  Copyright © 2026
//

import AppLog
import Foundation

private let agentXPCLog = AppLog.make(category: "FanCurveAgentXPC")

final class FanCurveAgentXPCService: NSObject, NSXPCListenerDelegate, FanCurveAgentXPCProtocol {
    private let controller: AgentController
    private let listener: NSXPCListener

    init(
        controller: AgentController,
        serviceName: String = FanCurveAgentXPC.serviceName
    ) {
        self.controller = controller
        self.listener = NSXPCListener(machServiceName: serviceName)
        super.init()
        self.listener.delegate = self
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
        connection.invalidationHandler = {
            agentXPCLog.info("agent.xpc.connection.invalidated")
        }
        connection.interruptionHandler = {
            agentXPCLog.info("agent.xpc.connection.interrupted")
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

    func requestRefresh(reply: @escaping @Sendable (Bool, String?) -> Void) {
        agentXPCLog.info("agent.xpc.refresh.requested")
        controller.requestTick()
        reply(true, nil)
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
        SharedConfigPush.post()
        controller.requestTick()
    }
}
