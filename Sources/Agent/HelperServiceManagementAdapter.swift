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

private enum HelperServiceManagementConstants {
  static let unregisterPollInterval = Duration.milliseconds(100)
  static let unregisterTimeoutSeconds: Int64 = 5
  static let unregisterTimeout = Duration.seconds(unregisterTimeoutSeconds)
}

private typealias ServiceContinuation = CheckedContinuation<Void, Error>

// MARK: - HelperServiceManagementError

private enum HelperServiceManagementError: LocalizedError {
  case unregisterTimedOut

  var errorDescription: String? {
    "System Helper unregister did not finish within \(HelperServiceManagementConstants.unregisterTimeoutSeconds) seconds"
  }
}

// MARK: - ServiceManagementAdapters

extension ServiceManagementAdapters {
  static func helper() -> any HelperServiceManaging {
    HelperServiceManagementAdapter()
  }
}

// MARK: - HelperServiceManagementAdapter

final class HelperServiceManagementAdapter: HelperServiceManaging, @unchecked Sendable {
  private let service: SMAppService

  init(plistName: String = generatedHelperDaemonPlistName) {
    self.service = SMAppService.daemon(plistName: plistName)
  }

  var status: ManagedServiceStatus {
    ManagedServiceStatus(service.status)
  }

  func register() async throws {
    await Task.yield()
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

  func unregister() async throws {
    helperServiceManagementLog.notice("helper.service.unregister.started")
    do {
      try await withCheckedThrowingContinuation { (continuation: ServiceContinuation) in
        service.unregister { error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume()
          }
        }
      }
      try await waitUntilUnregistered()
      helperServiceManagementLog.notice(
        "helper.service.unregister.finished status=\(status.description, privacy: .public)"
      )
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

  private func waitUntilUnregistered() async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(
      by: HelperServiceManagementConstants.unregisterTimeout
    )
    while status == .enabled {
      guard clock.now < deadline else {
        throw HelperServiceManagementError.unregisterTimedOut
      }
      try await clock.sleep(
        for: HelperServiceManagementConstants.unregisterPollInterval
      )
    }
  }
}
