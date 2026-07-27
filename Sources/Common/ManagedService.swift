//
//  ManagedService.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let managedServiceLog = AppLog.make(category: "ManagedService")

// MARK: - ManagedService

enum ManagedService {
  static func installOrRepair(
    helperService: any HelperServiceManaging
  ) -> ManagedServiceMutationResult {
    let statusBefore = helperService.status
    var currentOperation = "register"
    var statusAfterUnregister: ManagedServiceStatus?

    do {
      if statusBefore == .enabled {
        currentOperation = "unregister"
        managedServiceLog.notice(
          "helper.repair.unregister.started status=\(statusBefore.description, privacy: .public)"
        )
        try helperService.unregister()
        statusAfterUnregister = helperService.status
        managedServiceLog.notice(
          "helper.repair.unregister.finished status=\(helperService.status.description, privacy: .public)"
        )
      }

      currentOperation = "register"
      managedServiceLog.notice(
        "helper.install.register.started status=\(helperService.status.description, privacy: .public)"
      )
      try helperService.register()
      managedServiceLog.notice(
        "helper.install.register.finished status=\(helperService.status.description, privacy: .public)"
      )
      return ManagedServiceMutationResult(
        statusBefore: statusBefore,
        statusAfterUnregister: statusAfterUnregister,
        statusAfterRegister: helperService.status,
        errorDescription: nil
      )
    } catch {
      managedServiceLog.error(
        "helper.install.failed operation=\(currentOperation, privacy: .public) status=\(helperService.status.description, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-agent"
      )
      return ManagedServiceMutationResult(
        statusBefore: statusBefore,
        statusAfterUnregister: statusAfterUnregister,
        statusAfterRegister: nil,
        errorDescription: error.localizedDescription
      )
    }
  }
}

// MARK: - ManagedServiceStatus

enum ManagedServiceStatus: Sendable, Equatable, CustomStringConvertible {
  case enabled
  case notFound
  case notRegistered
  case requiresApproval
  case unknown(rawValue: Int)

  var description: String {
    switch self {
    case .enabled:
      return "enabled"
    case .notFound:
      return "notFound"
    case .notRegistered:
      return "notRegistered"
    case .requiresApproval:
      return "requiresApproval"
    case .unknown(let rawValue):
      return "unknown(\(rawValue))"
    }
  }
}

// MARK: - ManagedServiceMutationResult

struct ManagedServiceMutationResult: Sendable, Equatable {
  let statusBefore: ManagedServiceStatus
  let statusAfterUnregister: ManagedServiceStatus?
  let statusAfterRegister: ManagedServiceStatus?
  let errorDescription: String?
}

// MARK: - BackgroundAgentServiceManaging

protocol BackgroundAgentServiceManaging {
  var status: ManagedServiceStatus { get }

  func register() throws
  func unregister() throws
  func openSystemSettings()
}

// MARK: - HelperServiceManaging

protocol HelperServiceManaging {
  var status: ManagedServiceStatus { get }

  func register() throws
  func unregister() throws
  func openSystemSettings()
}
