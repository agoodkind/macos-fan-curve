//
//  HelperServiceManagementAdapter.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation
import ServiceManagement

private let helperServiceManagementLog = AppLog.make(category: "HelperServiceManagement")

extension ServiceManagementAdapters {
  static func helper() -> any HelperServiceManaging {
    HelperServiceManagementAdapter()
  }
}

// MARK: - HelperServiceManagementAdapter

final class HelperServiceManagementAdapter: HelperServiceManaging {
  private let service: SMAppService

  init(plistName: String = generatedHelperDaemonPlistName) {
    self.service = SMAppService.daemon(plistName: plistName)
  }

  var status: ManagedServiceStatus {
    ManagedServiceStatus(service.status)
  }

  func register() throws {
    helperServiceManagementLog.notice("helper.service.register.started")
    do {
      try service.register()
      helperServiceManagementLog.notice("helper.service.register.finished")
    } catch {
      helperServiceManagementLog.error(
        "helper.service.register.failed error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-agent"
      )
      throw error
    }
  }

  func unregister() throws {
    helperServiceManagementLog.notice("helper.service.unregister.started")
    do {
      try service.unregister()
      helperServiceManagementLog.notice("helper.service.unregister.finished")
    } catch {
      helperServiceManagementLog.error(
        "helper.service.unregister.failed error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-agent"
      )
      throw error
    }
  }

  func openSystemSettings() {
    helperServiceManagementLog.notice("helper.service.settings.opened")
    SMAppService.openSystemSettingsLoginItems()
  }
}
