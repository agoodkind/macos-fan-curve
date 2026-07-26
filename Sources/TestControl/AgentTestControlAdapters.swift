//
//  AgentTestControlAdapters.swift
//  FanCurveAgent
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import AppLog
  import Foundation

  private let agentTestControlAdaptersLog = AppLog.make(
    category: "AgentTestControlAdapters"
  )

  enum AgentTestControlAdapters {
    static func helperService(
      mode: TestControlRuntimeMode,
      production: () -> any HelperServiceManaging
    ) -> any HelperServiceManaging {
      switch mode {
      case .production:
        return production()
      case .controlled(let runtime):
        return ControlledHelperServiceAdapter(runtime: runtime)
      case .refused(let path):
        return RefusedHelperServiceAdapter(path: path)
      }
    }

    static func fanHardware(
      mode: TestControlRuntimeMode,
      production: () -> any FanHardware
    ) -> any FanHardware {
      switch mode {
      case .production:
        return production()
      case .controlled(let runtime):
        return ControlledFanHardware(runtime: runtime)
      case .refused(let path):
        return RefusedFanHardware(path: path)
      }
    }
  }

  final class TestControlAgentXPCFaultController:
    FanCurveAgentXPCFaultControlling,
    @unchecked Sendable
  {
    private let mode: TestControlRuntimeMode
    private let faultObserver: @Sendable (TestXPCFault) -> Void

    init(
      mode: TestControlRuntimeMode,
      faultObserver: @escaping @Sendable (TestXPCFault) -> Void = { fault in
        _ = fault
      }
    ) {
      self.mode = mode
      self.faultObserver = faultObserver
    }

    func consumeFault(
      at boundary: FanCurveAgentXPCFaultBoundary
    ) -> FanCurveAgentXPCFaultEffect {
      guard case .controlled(let runtime) = mode else {
        return .inactive
      }
      do {
        let state = try runtime.refresh()
        let effect = Self.effect(for: state.xpcFault, at: boundary)
        guard effect != .inactive else {
          return .inactive
        }
        guard try runtime.consumeFault(state.xpcFault) else {
          return .inactive
        }
        faultObserver(state.xpcFault)
        return effect
      } catch {
        agentTestControlAdaptersLog.error(
          "test_control.agent_xpc.fault_check_failed error=\(error.localizedDescription, privacy: .public) recovery=skip-fault"
        )
        return .inactive
      }
    }

    private static func effect(
      for fault: TestXPCFault,
      at boundary: FanCurveAgentXPCFaultBoundary
    ) -> FanCurveAgentXPCFaultEffect {
      switch (boundary, fault) {
      case (.command, .malformedReply):
        return .malformedReply
      case (.command, .rejectedCommand):
        return .rejectCommand
      case (.command, .interruption),
        (.currentState, .interruption),
        (.ownership, .interruption):
        return .terminateAgent
      case (.currentState, .malformedInitialState):
        return .malformedInitialState
      case (.runtimeEvent, .duplicateEvent):
        return .duplicateEvent
      case (.runtimeEvent, .invalidation):
        return .invalidateConnection
      case (.runtimeEvent, .malformedEvent):
        return .malformedEvent
      default:
        return .inactive
      }
    }
  }

  private final class RefusedHelperServiceAdapter: HelperServiceManaging {
    private let path: String

    init(path: String) {
      self.path = path
    }

    var status: ManagedServiceStatus {
      agentTestControlAdaptersLog.error(
        "test_control.service.refused service=helper operation=status path=\(path, privacy: .public) recovery=return-unknown"
      )
      return .unknown(rawValue: -1)
    }

    func register() throws {
      try refuse(operation: "register")
    }

    func unregister() throws {
      try refuse(operation: "unregister")
    }

    func openSystemSettings() {
      agentTestControlAdaptersLog.error(
        "test_control.service.refused service=helper operation=open_system_settings path=\(path, privacy: .public) recovery=skip-operation"
      )
    }

    private func refuse(operation: String) throws {
      agentTestControlAdaptersLog.error(
        "test_control.service.refused service=helper operation=\(operation, privacy: .public) path=\(path, privacy: .public) recovery=return-error"
      )
      throw TestControlRefusalError(path: path)
    }
  }

  private final class RefusedFanHardware: FanHardware, @unchecked Sendable {
    private let path: String

    init(path: String) {
      self.path = path
    }

    func shutdown() {
      agentTestControlAdaptersLog.error(
        "test_control.hardware.refused operation=shutdown path=\(path, privacy: .public) recovery=skip-operation"
      )
    }

    func readAndApply(
      fanCount _: UInt,
      tempKeys _: [String],
      setFans _: [(index: UInt, rpm: Float)],
      autoFans _: [UInt],
      priority _: Int?
    ) -> FanHardwareBatchRead {
      agentTestControlAdaptersLog.error(
        "test_control.hardware.refused operation=batch path=\(path, privacy: .public) recovery=return-empty-batch"
      )
      return FanHardwareBatchRead(fans: [], temps: [:])
    }

    func getOwnership() throws -> [AgentOwnershipEntry] {
      try refuse(operation: "ownership")
    }

    func setFanRPM(
      _: UInt,
      rpm _: Float,
      priority _: Int?
    ) throws {
      try refuse(operation: "set_fan_rpm")
    }

    func setFanAuto(
      _: UInt,
      priority _: Int?
    ) throws {
      try refuse(operation: "set_fan_auto")
    }

    private func refuse(operation: String) throws -> Never {
      agentTestControlAdaptersLog.error(
        "test_control.hardware.refused operation=\(operation, privacy: .public) path=\(path, privacy: .public) recovery=return-error"
      )
      throw TestControlRefusalError(path: path)
    }
  }
#endif
