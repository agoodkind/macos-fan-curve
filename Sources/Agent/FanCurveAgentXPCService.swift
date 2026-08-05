//
//  FanCurveAgentXPCService.swift
//  FanCurveAgent
//
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Darwin
import Foundation

let agentXPCLog = AppLog.make(category: "FanCurveAgentXPC")

// MARK: - FanCurveAgentXPCService

final class FanCurveAgentXPCService: NSObject, @unchecked Sendable {
  private let controller: AgentController
  let helperService: any HelperServiceManaging
  private let listener: NSXPCListener
  private let faultController: any FanCurveAgentXPCFaultControlling
  private let processTerminator: @Sendable () -> Void
  private let reconciler: SystemHelperLifecycleReconciler
  private let callbackLock = NSLock()
  private var eventCallbacks: [ObjectIdentifier: FanCurveAgentXPCEventProtocol] = [:]
  private var connections: [ObjectIdentifier: NSXPCConnection] = [:]

  convenience init(
    controller: AgentController,
    helperService: any HelperServiceManaging,
    reconciler: SystemHelperLifecycleReconciler,
    serviceName: String = FanCurveAgentXPC.serviceName,
    faultController: any FanCurveAgentXPCFaultControlling =
      ProductionAgentXPCFaultControl(),
    processTerminator: @escaping @Sendable () -> Void = { Darwin.exit(0) }
  ) {
    self.init(
      controller: controller,
      listener: NSXPCListener(machServiceName: serviceName),
      helperService: helperService,
      reconciler: reconciler,
      faultController: faultController,
      processTerminator: processTerminator
    )
  }

  init(
    controller: AgentController,
    listener: NSXPCListener,
    helperService: any HelperServiceManaging,
    reconciler: SystemHelperLifecycleReconciler,
    faultController: any FanCurveAgentXPCFaultControlling =
      ProductionAgentXPCFaultControl(),
    processTerminator: @escaping @Sendable () -> Void = { Darwin.exit(0) }
  ) {
    self.controller = controller
    self.helperService = helperService
    self.listener = listener
    self.reconciler = reconciler
    self.faultController = faultController
    self.processTerminator = processTerminator
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

  func reconcileSystemHelper(
    trigger: SystemHelperReconcileTrigger
  ) async -> SystemHelperRuntimeState {
    agentXPCLog.notice(
      "agent.xpc.system_helper.reconcile.started operation=\(trigger.operation.rawValue, privacy: .public)"
    )
    let state = await reconciler.reconcile(trigger: trigger)
    agentXPCLog.notice(
      "agent.xpc.system_helper.reconcile.finished operation=\(trigger.operation.rawValue, privacy: .public) state=\(state.logName, privacy: .public)"
    )
    return state
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
      self.removeConnection(connection, reason: "connection-invalidated")
    }
    connection.interruptionHandler = {
      agentXPCLog.info("agent.xpc.connection.interrupted")
      self.removeConnection(connection, reason: "connection-interrupted")
    }
    callbackLock.withLock {
      connections[ObjectIdentifier(connection)] = connection
    }
    connection.resume()
    agentXPCLog.info("agent.xpc.connection.accepted")
    return true
  }
}

extension FanCurveAgentXPCService: FanCurveAgentXPCProtocol {
  func getCurrentState(reply: @Sendable (Bool, Data?, String?) -> Void) {
    agentXPCLog.debug("agent.xpc.current_state.requested")
    let faultEffect = faultController.consumeFault(at: .currentState)
    switch faultEffect {
    case .malformedInitialState:
      agentXPCLog.notice(
        "agent.xpc.current_state.fault_injected kind=malformed_initial_state"
      )
      reply(true, Data("{".utf8), nil)
      return
    case .terminateAgent:
      agentXPCLog.notice("agent.xpc.current_state.fault_injected kind=interruption")
      terminateAgentWithoutReply(boundary: "current-state")
      return
    default:
      break
    }
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

    let connectionID = ObjectIdentifier(currentConnection)
    let callbackCount = callbackLock.withLock {
      eventCallbacks[connectionID] = callback
      return eventCallbacks.count
    }
    agentXPCLog.info(
      "agent.xpc.events.registered callbacks=\(callbackCount, privacy: .public)"
    )
    publishRuntimeState(controller.currentRuntimeStateForXPC())
    reply(true, nil)
  }

  func requestRefresh(reply: @Sendable (Bool, String?) -> Void) {
    agentXPCLog.info("agent.xpc.refresh.requested")
    controller.requestTickIfRunning()
    reply(true, nil)
  }

  func sendCommand(
    _ commandData: Data,
    reply: @escaping @Sendable (Bool, Data?, String?) -> Void
  ) {
    do {
      let command = try JSONDecoder().decode(AgentCommand.self, from: commandData)
      agentXPCLog.info("agent.xpc.command.received kind=\(command.logName, privacy: .public)")
      let faultEffect = faultController.consumeFault(at: .command)
      if case .terminateAgent = faultEffect {
        agentXPCLog.notice("agent.xpc.command.fault_injected kind=interruption")
        terminateAgentWithoutReply(boundary: "command")
        return
      }
      if case .rejectCommand = faultEffect {
        agentXPCLog.notice("agent.xpc.command.fault_injected kind=rejected_command")
        reply(false, nil, "Controlled command rejected")
        return
      }
      Task {
        let response = await self.handleCommand(command)
        if case .malformedReply = faultEffect {
          agentXPCLog.notice("agent.xpc.command.fault_injected kind=malformed_reply")
          reply(true, Data("{".utf8), nil)
          return
        }
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
    let faultEffect = faultController.consumeFault(at: .ownership)
    if case .terminateAgent = faultEffect {
      agentXPCLog.notice("agent.xpc.ownership.fault_injected kind=interruption")
      terminateAgentWithoutReply(boundary: "ownership")
      return
    }
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
    controller.requestTickIfRunning()
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
    agentXPCLog.notice("agent.xpc.command.helper_install.started owner=reconciler")
    let state = await reconcileSystemHelper(trigger: .forcedRepair)
    if case .running = state {
      agentXPCLog.notice(
        "agent.xpc.command.helper_install.finished result=verified-running"
      )
      return AgentCommandResponse(accepted: true, message: nil)
    }
    let failure = state.commandFailureMessage
    agentXPCLog.error(
      "agent.xpc.command.helper_install.failed state=\(state.logName, privacy: .public) error=\(failure, privacy: .public) recovery=return-durable-failure"
    )
    return AgentCommandResponse(accepted: false, message: failure)
  }

  func handleFanAutoCommand(_ fanIndex: UInt) async -> AgentCommandResponse {
    do {
      try await controller.setFanAuto(fanIndex)
      controller.requestTickIfRunning()
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
      controller.requestTickIfRunning()
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

  func publishRuntimeState(_ runtimeState: RuntimeState) {
    let callbacks = currentEventCallbacks()
    guard !callbacks.isEmpty else { return }
    let faultEffect = faultController.consumeFault(at: .runtimeEvent)
    if case .invalidateConnection = faultEffect {
      agentXPCLog.notice("agent.xpc.events.fault_injected kind=invalidation")
      invalidateConnections()
      return
    }
    do {
      let encodedState = try JSONEncoder().encode(runtimeState)
      let data: Data
      if case .malformedEvent = faultEffect {
        data = Data("{".utf8)
        agentXPCLog.notice("agent.xpc.events.fault_injected kind=malformed_event")
      } else {
        data = encodedState
      }
      for callback in callbacks {
        callback.agentRuntimeStateDidUpdate(data)
        if case .duplicateEvent = faultEffect {
          callback.agentRuntimeStateDidUpdate(data)
        }
      }
      if case .duplicateEvent = faultEffect {
        agentXPCLog.notice("agent.xpc.events.fault_injected kind=duplicate_event")
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
    callbackLock.withLock {
      Array(eventCallbacks.values)
    }
  }

  func removeConnection(_ connection: NSXPCConnection, reason: String) {
    let connectionID = ObjectIdentifier(connection)
    let callbackCount = callbackLock.withLock {
      connections.removeValue(forKey: connectionID)
      eventCallbacks.removeValue(forKey: connectionID)
      return eventCallbacks.count
    }
    agentXPCLog.info(
      "agent.xpc.events.connection_cleared reason=\(reason, privacy: .public) remaining_callbacks=\(callbackCount, privacy: .public)"
    )
  }

  func invalidateConnections() {
    let currentConnections = callbackLock.withLock {
      let result = Array(connections.values)
      connections.removeAll()
      eventCallbacks.removeAll()
      return result
    }
    for connection in currentConnections {
      connection.invalidate()
    }
  }

  func terminateAgentWithoutReply(boundary: String) {
    processTerminator()
    agentXPCLog.error(
      "agent.xpc.process_termination.returned boundary=\(boundary, privacy: .public) recovery=invalidate-connections-without-reply"
    )
    invalidateConnections()
  }
}
