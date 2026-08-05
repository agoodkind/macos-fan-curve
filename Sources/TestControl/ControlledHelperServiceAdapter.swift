//
//  ControlledHelperServiceAdapter.swift
//  FanCurveAgent
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import AppLog
  import Foundation

  private let controlledHelperServiceLog = AppLog.make(
    category: "ControlledHelperService"
  )

  final class ControlledHelperServiceAdapter:
    HelperServiceManaging,
    @unchecked Sendable
  {
    private let stateLock = NSLock()
    private let runtime: TestControlRuntime
    private var controlledRevision: TestControlRevision?
    private var controlledStatus = TestManagedServiceStatus.notRegistered

    init(runtime: TestControlRuntime) {
      self.runtime = runtime
    }

    var status: ManagedServiceStatus {
      do {
        let state = try runtime.refresh()
        let serviceStatus = status(for: state)
        try runtime.record(
          .serviceMutation(
            service: .helper,
            operation: .status,
            result: .succeed
          ),
          state: state
        )
        controlledHelperServiceLog.debug(
          "test_control.service.status service=helper status=\(serviceStatus.rawValue, privacy: .public) revision=\(state.revision.value, privacy: .public)"
        )
        return ManagedServiceStatus(serviceStatus)
      } catch {
        controlledHelperServiceLog.error(
          "test_control.service.status_failed service=helper error=\(error.localizedDescription, privacy: .public) recovery=return-unknown"
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
      _ = status(for: state)
      let directive = state.services.nextOperation
      try runtime.record(
        .serviceMutation(
          service: .helper,
          operation: operation,
          result: directive
        ),
        state: state
      )
      controlledHelperServiceLog.info(
        "test_control.service.operation service=helper operation=\(operation.rawValue, privacy: .public) revision=\(state.revision.value, privacy: .public)"
      )
      if case let .fail(code, message) = directive {
        controlledHelperServiceLog.error(
          "test_control.service.operation_failed service=helper operation=\(operation.rawValue, privacy: .public) code=\(code, privacy: .public) recovery=return-controlled-error"
        )
        throw TestControlOperationError(code: code, message: message)
      }
      updateStatus(after: operation)
    }

    private func status(for state: TestControlState) -> TestManagedServiceStatus {
      stateLock.withLock {
        if controlledRevision != state.revision {
          controlledRevision = state.revision
          controlledStatus = state.services.helperStatus
        }
        return controlledStatus
      }
    }

    private func updateStatus(after operation: TestServiceOperation) {
      stateLock.withLock {
        switch operation {
        case .register:
          controlledStatus = .enabled
        case .unregister:
          controlledStatus = .notRegistered
        case .openSystemSettings, .status:
          break
        }
      }
    }
  }
#endif
