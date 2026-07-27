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

  final class ControlledHelperServiceAdapter: HelperServiceManaging {
    private let runtime: TestControlRuntime

    init(runtime: TestControlRuntime) {
      self.runtime = runtime
    }

    var status: ManagedServiceStatus {
      do {
        let state = try runtime.refresh()
        let controlledStatus = state.services.helperStatus
        try runtime.record(
          .serviceMutation(
            service: .helper,
            operation: .status,
            result: .succeed
          ),
          state: state
        )
        controlledHelperServiceLog.debug(
          "test_control.service.status service=helper status=\(controlledStatus.rawValue, privacy: .public) revision=\(state.revision.value, privacy: .public)"
        )
        return ManagedServiceStatus(controlledStatus)
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
    }
  }
#endif
