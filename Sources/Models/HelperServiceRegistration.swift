//
//  HelperServiceRegistration.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-21.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation
import ServiceManagement

enum HelperServiceRegistration {
  private static let log = AppLog.make(category: "HelperServiceRegistration")

  enum Plan: Equatable, Sendable {
    case register
    case unregisterThenRegister

    static func resolve(serviceEnabled: Bool) -> Plan {
      if serviceEnabled {
        return .unregisterThenRegister
      }
      return .register
    }
  }

  @available(macOS 13.0, *)
  @MainActor
  static func register(service: SMAppService) -> HelperServiceMutationResult {
    let statusBefore = describeStatus(service.status)
    let registrationPlan = Plan.resolve(serviceEnabled: service.status == .enabled)
    do {
      if registrationPlan == .unregisterThenRegister {
        log.notice(
          "helper.register.reinstall.started status=\(statusBefore, privacy: .public)"
        )
        try service.unregister()
        log.notice(
          "helper.register.reinstall.unregistered status=\(describeStatus(service.status), privacy: .public)"
        )
      }
      try service.register()
      return HelperServiceMutationResult(
        statusBefore: statusBefore,
        statusAfterRegister: describeStatus(service.status),
        errorDescription: nil
      )
    } catch {
      log.error(
        "helper.register.service.failed status=\(statusBefore, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-ui"
      )
      return HelperServiceMutationResult(
        statusBefore: statusBefore,
        statusAfterRegister: nil,
        errorDescription: error.localizedDescription
      )
    }
  }

  @available(macOS 13.0, *)
  private static func describeStatus(_ status: SMAppService.Status) -> String {
    switch status {
    case .enabled:
      "enabled"
    case .requiresApproval:
      "requiresApproval"
    case .notFound:
      "notFound"
    case .notRegistered:
      "notRegistered"
    default:
      "unknown(\(status.rawValue))"
    }
  }
}
