//
//  ServiceManagementAdapters.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation
import ServiceManagement

private let serviceManagementAdaptersLog = AppLog.make(category: "ServiceManagement")

// MARK: - ServiceManagementAdapters

enum ServiceManagementAdapters {
  static func backgroundAgent() -> any BackgroundAgentServiceManaging {
    BackgroundAgentServiceManagementAdapter()
  }
}

// MARK: - BackgroundAgentServiceManagementAdapter

final class BackgroundAgentServiceManagementAdapter: BackgroundAgentServiceManaging {
  private let service: SMAppService

  init(plistName: String = generatedAgentPlistName) {
    self.service = SMAppService.agent(plistName: plistName)
  }

  var status: ManagedServiceStatus {
    ManagedServiceStatus(service.status)
  }

  func register() throws {
    serviceManagementAdaptersLog.notice("agent.service.register.started")
    do {
      try service.register()
      serviceManagementAdaptersLog.notice("agent.service.register.finished")
    } catch {
      serviceManagementAdaptersLog.error(
        "agent.service.register.failed error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-app"
      )
      throw error
    }
  }

  func unregister() throws {
    serviceManagementAdaptersLog.notice("agent.service.unregister.started")
    do {
      try service.unregister()
      serviceManagementAdaptersLog.notice("agent.service.unregister.finished")
    } catch {
      serviceManagementAdaptersLog.error(
        "agent.service.unregister.failed error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-app"
      )
      throw error
    }
  }

  func openSystemSettings() {
    serviceManagementAdaptersLog.notice("agent.service.settings.opened")
    SMAppService.openSystemSettingsLoginItems()
  }
}

// MARK: - ManagedServiceStatus

extension ManagedServiceStatus {
  init(_ status: SMAppService.Status) {
    switch status {
    case .enabled:
      self = .enabled
    case .notFound:
      self = .notFound
    case .notRegistered:
      self = .notRegistered
    case .requiresApproval:
      self = .requiresApproval
    default:
      self = .unknown(rawValue: status.rawValue)
    }
  }
}
