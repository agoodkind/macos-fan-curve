//
//  TestControlAdapters.swift
//  FanCurve
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import AppLog
  import Foundation

  private let testControlAdaptersLog = AppLog.make(category: "TestControlAdapters")

  struct TestControlRefusalError: Error, Equatable, LocalizedError, Sendable {
    let path: String

    var errorDescription: String? {
      "Test control session is invalid: \(path)"
    }
  }

  enum TestControlRuntimeMode: @unchecked Sendable {
    case controlled(TestControlRuntime)
    case production
    case refused(path: String)

    static func resolve(
      participant: TestControlParticipant,
      activation: TestControlActivation = TestControlActivation.resolve()
    ) throws -> TestControlRuntimeMode {
      switch activation {
      case .production:
        testControlAdaptersLog.info(
          "test_control.composition.production participant=\(participant.rawValue, privacy: .public)"
        )
        return .production
      case .refused(let path):
        testControlAdaptersLog.error(
          "test_control.composition.refused participant=\(participant.rawValue, privacy: .public) path=\(path, privacy: .public) recovery=construct-refused-adapters"
        )
        return .refused(path: path)
      case let .controlled(sessionID, directory):
        let store = try TestControlSessionStore.open(at: directory)
        let initialState = try store.loadState()
        guard initialState.sessionID == sessionID else {
          throw TestControlError.invalidSession(
            expected: sessionID,
            actual: initialState.sessionID
          )
        }
        let controlledRuntime = try TestControlRuntime(
          store: store,
          participant: participant
        )
        testControlAdaptersLog.notice(
          "test_control.composition.controlled participant=\(participant.rawValue, privacy: .public) session=\(sessionID.uuidString, privacy: .public) revision=\(initialState.revision.value, privacy: .public)"
        )
        return .controlled(controlledRuntime)
      }
    }
  }

  enum TestControlProcessRuntimes {
    static let app = resolve(participant: .app)
    static let agent = resolve(participant: .agent)

    private static func resolve(
      participant: TestControlParticipant
    ) -> TestControlRuntimeMode {
      let activation = TestControlActivation.resolve()
      do {
        return try TestControlRuntimeMode.resolve(
          participant: participant,
          activation: activation
        )
      } catch {
        let path: String
        switch activation {
        case .controlled(_, let directory):
          path = directory.path
        case .refused(let refusedPath):
          path = refusedPath
        case .production:
          path = "<production-resolution-error>"
        }
        testControlAdaptersLog.error(
          "test_control.composition.resolve_failed participant=\(participant.rawValue, privacy: .public) path=\(path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=construct-refused-adapters"
        )
        return .refused(path: path)
      }
    }
  }

  enum TestControlAdapters {
    static func backgroundAgentService(
      mode: TestControlRuntimeMode,
      production: () -> any BackgroundAgentServiceManaging
    ) -> any BackgroundAgentServiceManaging {
      switch mode {
      case .production:
        return production()
      case .controlled(let runtime):
        return ControlledBackgroundAgentServiceAdapter(runtime: runtime)
      case .refused(let path):
        return RefusedBackgroundAgentServiceAdapter(path: path)
      }
    }
  }

  final class TestControlAgentClientController:
    FanCurveAgentClientControlling,
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

    func connectionGate() -> FanCurveAgentClientGate {
      switch mode {
      case .production:
        return .allowed
      case .refused(let path):
        return .refused(TestControlRefusalError(path: path).localizedDescription)
      case .controlled(let runtime):
        do {
          let state = try runtime.refresh()
          guard state.services.backgroundAgentStatus == .enabled else {
            return .refused("Controlled Background Agent is not enabled")
          }
          return .allowed
        } catch {
          testControlAdaptersLog.error(
            "test_control.app_xpc.gate_failed error=\(error.localizedDescription, privacy: .public) recovery=refuse-connection"
          )
          return .refused(error.localizedDescription)
        }
      }
    }

    func consumeReconnectFault() -> Bool {
      guard case .controlled(let runtime) = mode else {
        return false
      }
      do {
        guard try runtime.consumeFault(.reconnect) else {
          return false
        }
        faultObserver(.reconnect)
        return true
      } catch {
        testControlAdaptersLog.error(
          "test_control.app_xpc.reconnect_fault_check_failed error=\(error.localizedDescription, privacy: .public) recovery=skip-fault"
        )
        return false
      }
    }

    func recordCommand(_ command: AgentCommand) {
      record(.appToAgentCommand(command: Self.testCommand(command)))
    }

    func recordEvent(_ event: FanCurveAgentClientControlEvent) {
      record(.xpcState(Self.testEvent(event)))
    }

    private func record(_ payload: TestControlEventPayload) {
      guard case .controlled(let runtime) = mode else {
        return
      }
      do {
        try runtime.record(payload)
      } catch {
        testControlAdaptersLog.error(
          "test_control.app_xpc.evidence_failed kind=\(payload.kind.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=continue-runtime"
        )
      }
    }

    private static func testCommand(_ command: AgentCommand) -> TestAppToAgentCommand {
      switch command {
      case .installOrRepairHelper:
        return .installOrRepairHelper
      case .openSystemSettings:
        return .openSystemSettings
      case .requestFanAuto:
        return .requestFanAuto
      case .requestFanRPM:
        return .requestFanRPM
      case .setApplyInBackground:
        return .setApplyInBackground
      case .setBoostEnabled:
        return .setBoostEnabled
      case .setCurve:
        return .setCurve
      case .setFanControlEnabled:
        return .setFanControlEnabled
      }
    }

    private static func testEvent(
      _ event: FanCurveAgentClientControlEvent
    ) -> TestXPCStateEvent {
      switch event {
      case .commandRejected:
        return .commandRejected
      case .commandReplyMalformed:
        return .commandReplyMalformed
      case .connected:
        return .connected
      case .connecting:
        return .connecting
      case .connectionAttemptGated:
        return .connectionAttemptGated
      case .disconnected:
        return .disconnected
      case .initialStateRejected:
        return .initialStateRejected
      case .reconnectScheduled:
        return .reconnectScheduled
      case .runtimeEventAccepted:
        return .runtimeEventAccepted
      case .runtimeEventRejected:
        return .runtimeEventRejected
      }
    }
  }

  private final class ControlledBackgroundAgentServiceAdapter:
    BackgroundAgentServiceManaging
  {
    private let runtime: TestControlRuntime

    init(runtime: TestControlRuntime) {
      self.runtime = runtime
    }

    var status: ManagedServiceStatus {
      do {
        let state = try runtime.refresh()
        let controlledStatus = state.services.backgroundAgentStatus
        try runtime.record(
          .serviceMutation(
            service: .backgroundAgent,
            operation: .status,
            result: .succeed
          ),
          state: state
        )
        testControlAdaptersLog.debug(
          "test_control.service.status service=background_agent status=\(controlledStatus.rawValue, privacy: .public) revision=\(state.revision.value, privacy: .public)"
        )
        return ManagedServiceStatus(controlledStatus)
      } catch {
        testControlAdaptersLog.error(
          "test_control.service.status_failed service=background_agent error=\(error.localizedDescription, privacy: .public) recovery=return-unknown"
        )
        return .unknown(rawValue: -1)
      }
    }

    func register() throws {
      try perform(.register)
    }

    func unregister() throws {
      try perform(.unregister)
    }

    func openSystemSettings() throws {
      try perform(.openSystemSettings)
    }

    private func perform(_ operation: TestServiceOperation) throws {
      let state = try runtime.refresh()
      let directive = state.services.nextOperation
      try runtime.record(
        .serviceMutation(
          service: .backgroundAgent,
          operation: operation,
          result: directive
        ),
        state: state
      )
      testControlAdaptersLog.info(
        "test_control.service.operation service=background_agent operation=\(operation.rawValue, privacy: .public) revision=\(state.revision.value, privacy: .public)"
      )
      if case let .fail(code, message) = directive {
        testControlAdaptersLog.error(
          "test_control.service.operation_failed service=background_agent operation=\(operation.rawValue, privacy: .public) code=\(code, privacy: .public) recovery=return-controlled-error"
        )
        throw TestControlOperationError(code: code, message: message)
      }
    }
  }

  private final class RefusedBackgroundAgentServiceAdapter:
    BackgroundAgentServiceManaging
  {
    private let path: String

    init(path: String) {
      self.path = path
    }

    var status: ManagedServiceStatus {
      testControlAdaptersLog.error(
        "test_control.service.refused service=background_agent operation=status path=\(path, privacy: .public) recovery=return-unknown"
      )
      return .unknown(rawValue: -1)
    }

    func register() throws {
      try refuse(operation: "register")
    }

    func unregister() throws {
      try refuse(operation: "unregister")
    }

    func openSystemSettings() throws {
      testControlAdaptersLog.error(
        "test_control.service.refused service=background_agent operation=open_system_settings path=\(path, privacy: .public) recovery=return-error"
      )
      throw TestControlRefusalError(path: path)
    }

    private func refuse(operation: String) throws {
      testControlAdaptersLog.error(
        "test_control.service.refused service=background_agent operation=\(operation, privacy: .public) path=\(path, privacy: .public) recovery=return-error"
      )
      throw TestControlRefusalError(path: path)
    }
  }

  extension ManagedServiceStatus {
    init(_ status: TestManagedServiceStatus) {
      switch status {
      case .approvalRequired:
        self = .requiresApproval
      case .enabled:
        self = .enabled
      case .notRegistered:
        self = .notRegistered
      }
    }
  }
#endif
