//
//  FanCurveAgentXPCService.swift
//  FanCurveAgent
//
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let agentXPCLog = AppLog.make(category: "FanCurveAgentXPC")

final class FanCurveAgentXPCService: NSObject, @unchecked Sendable {
  private let controller: AgentController
  private let helperService: any HelperServiceManaging
  private let listener: NSXPCListener
  private let callbackLock = NSLock()
  private var eventCallbacks: [FanCurveAgentXPCEventProtocol] = []

  init(
    controller: AgentController,
    serviceName: String = FanCurveAgentXPC.serviceName,
    helperService: any HelperServiceManaging = ServiceManagementAdapters.helper()
  ) {
    self.controller = controller
    self.helperService = helperService
    self.listener = NSXPCListener(machServiceName: serviceName)
    super.init()
    self.listener.delegate = self
    self.controller.runtimeSetupProvider = { [weak self] snapshot in
      guard let self else {
        return RuntimeSetupInputs(backgroundAgent: .satisfied, helper: .required)
      }
      return Self.currentRuntimeSetupInputs(
        helperStatus: self.helperService.status,
        snapshot: snapshot
      )
    }
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
}

extension FanCurveAgentXPCService: NSXPCListenerDelegate {
  func listener(
    _: NSXPCListener,
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
}

extension FanCurveAgentXPCService: FanCurveAgentXPCProtocol {
  func getCurrentState(reply: @Sendable (Bool, Data?, String?) -> Void) {
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

  func registerForEvents(reply: @Sendable (Bool, String?) -> Void) {
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

  func requestRefresh(reply: @Sendable (Bool, String?) -> Void) {
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
        let rows = try await controller.getOwnership()
        let data = try JSONEncoder().encode(rows)
        agentXPCLog.debug(
          "agent.xpc.ownership.returned count=\(rows.count, privacy: .public)"
        )
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
    reply: @Sendable (Bool, String?) -> Void
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
    reply: @Sendable (Bool, String?) -> Void
  ) {
    agentXPCLog.info("agent.xpc.boost.set requested=\(enabled, privacy: .public)")
    controller.sharedConfig.defaults.set(enabled, forKey: SharedConfigKeys.boostEnabled)
    publishConfigChange()
    reply(true, nil)
  }

  func setCurve(
    _ curveData: Data,
    reply: @Sendable (Bool, String?) -> Void
  ) {
    agentXPCLog.info("agent.xpc.curve.set bytes=\(curveData.count, privacy: .public)")
    controller.sharedConfig.defaults.set(curveData, forKey: SharedConfigKeys.curvePoints)
    publishConfigChange()
    reply(true, nil)
  }
}

extension FanCurveAgentXPCService {
  func publishConfigChange() {
    controller.sharedConfig.defaults.synchronize()
    controller.requestTick()
  }

  func handleCommand(_ command: AgentCommand) async -> AgentCommandResponse {
    switch command {
    case .installOrRepairHelper:
      return await installOrRepairHelperCommandResponse()
    case .openSystemSettings:
      return await openSystemSettingsCommandResponse()
    case .requestFanAuto(let fanIndex):
      return await handleFanAutoCommand(fanIndex)
    case .requestFanRPM(let request):
      return await handleFanRPMCommand(request)
    case .setApplyInBackground(let enabled):
      return handleSetApplyInBackground(enabled)
    case .setBoostEnabled(let enabled):
      return handleSetBoostEnabled(enabled)
    case .setCurve(let update):
      return handleSetCurve(update)
    case .setFanControlEnabled(let enabled):
      return handleSetFanControlEnabled(enabled)
    }
  }

  func installOrRepairHelperCommandResponse() async -> AgentCommandResponse {
    agentXPCLog.notice("agent.xpc.command.helper_install.started owner=agent")
    let result = await MainActor.run {
      HelperServiceRegistration.installOrRepair(service: helperService)
    }
    if let errorDescription = result.errorDescription {
      agentXPCLog.error(
        "agent.xpc.command.helper_install.failed status=\(result.statusBefore.description, privacy: .public) error=\(errorDescription, privacy: .public) recovery=return-error"
      )
      return AgentCommandResponse(accepted: false, message: errorDescription)
    }

    agentXPCLog.notice(
      "agent.xpc.command.helper_install.finished status=\(result.statusAfterRegister?.description ?? "unknown", privacy: .public)"
    )
    controller.requestTick()
    return AgentCommandResponse(accepted: true, message: nil)
  }

  func openSystemSettingsCommandResponse() async -> AgentCommandResponse {
    guard #available(macOS 13.0, *) else {
      return AgentCommandResponse(
        accepted: false,
        message: "System Settings action requires macOS 13"
      )
    }
    await MainActor.run {
      helperService.openSystemSettings()
    }
    agentXPCLog.notice("agent.xpc.command.system_settings.opened owner=agent")
    return AgentCommandResponse(accepted: true, message: nil)
  }

  func handleFanAutoCommand(_ fanIndex: UInt) async -> AgentCommandResponse {
    do {
      try await controller.setFanAuto(fanIndex)
      controller.requestTick()
      return AgentCommandResponse(accepted: true, message: nil)
    } catch {
      agentXPCLog.notice(
        "agent.xpc.command.fan_auto_failed fan=\(fanIndex, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error"
      )
      return AgentCommandResponse(accepted: false, message: error.localizedDescription)
    }
  }

  func handleFanRPMCommand(
    _ request: AgentFanRPMRequest
  ) async -> AgentCommandResponse {
    do {
      try await controller.setFanRPM(request.fanIndex, rpm: request.rpm)
      controller.requestTick()
      return AgentCommandResponse(accepted: true, message: nil)
    } catch {
      agentXPCLog.notice(
        "agent.xpc.command.fan_rpm_failed fan=\(request.fanIndex, privacy: .public) rpm=\(request.rpm, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error"
      )
      return AgentCommandResponse(accepted: false, message: error.localizedDescription)
    }
  }

  func handleSetApplyInBackground(_ enabled: Bool) -> AgentCommandResponse {
    controller.sharedConfig.defaults.set(
      enabled,
      forKey: SharedConfigKeys.applyInBackground
    )
    publishConfigChange()
    return AgentCommandResponse(accepted: true, message: nil)
  }

  func handleSetBoostEnabled(_ enabled: Bool) -> AgentCommandResponse {
    controller.sharedConfig.defaults.set(enabled, forKey: SharedConfigKeys.boostEnabled)
    publishConfigChange()
    return AgentCommandResponse(accepted: true, message: nil)
  }

  func handleSetCurve(_ update: AgentCurveUpdate) -> AgentCommandResponse {
    do {
      let data = try JSONEncoder().encode(CurveColumns.normalize(update.points))
      controller.sharedConfig.defaults.set(data, forKey: SharedConfigKeys.curvePoints)
      controller.sharedConfig.defaults.set(
        update.interpolationMode.rawValue,
        forKey: SharedConfigKeys.interpolationMode
      )
      publishConfigChange()
      return AgentCommandResponse(accepted: true, message: nil)
    } catch {
      agentXPCLog.error(
        "agent.xpc.command.curve_encode_failed point_count=\(update.points.count, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error"
      )
      return AgentCommandResponse(accepted: false, message: error.localizedDescription)
    }
  }

  func handleSetFanControlEnabled(_ enabled: Bool) -> AgentCommandResponse {
    controller.sharedConfig.defaults.set(enabled, forKey: SharedConfigKeys.curveActive)
    publishConfigChange()
    return AgentCommandResponse(accepted: true, message: nil)
  }

  static func currentRuntimeSetupInputs(
    helperStatus: ManagedServiceStatus,
    snapshot: AgentSnapshot?
  ) -> RuntimeSetupInputs {
    RuntimeSetupInputs(
      backgroundAgent: .satisfied,
      helper: currentHelperRequirement(helperStatus: helperStatus, snapshot: snapshot)
    )
  }

  static func currentHelperRequirement(
    helperStatus: ManagedServiceStatus,
    snapshot: AgentSnapshot?
  ) -> RuntimeServiceRequirement {
    switch helperStatus {
    case .requiresApproval:
      return .approvalRequired
    case .enabled:
      return snapshot?.helperReachable == true ? .satisfied : .required
    case .notFound, .notRegistered, .unknown:
      return .required
    }
  }

  func publishRuntimeState(_ runtimeState: RuntimeState) {
    let callbacks = currentEventCallbacks()
    guard !callbacks.isEmpty else { return }
    do {
      let data = try JSONEncoder().encode(runtimeState)
      for callback in callbacks {
        callback.agentRuntimeStateDidUpdate(data)
      }
      agentXPCLog.debug(
        "agent.xpc.events.runtime_state.sent callbacks=\(callbacks.count, privacy: .public)"
      )
    } catch {
      agentXPCLog.error(
        "agent.xpc.events.runtime_state.encode_failed error=\(error.localizedDescription, privacy: .public) recovery=drop-event"
      )
    }
  }

  func currentEventCallbacks() -> [FanCurveAgentXPCEventProtocol] {
    callbackLock.lock()
    defer { callbackLock.unlock() }
    return eventCallbacks
  }

  func clearEventCallbacks(reason: String) {
    callbackLock.lock()
    eventCallbacks.removeAll()
    callbackLock.unlock()
    agentXPCLog.info("agent.xpc.events.cleared reason=\(reason, privacy: .public)")
  }
}
