//
//  XPCClient.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026, all rights reserved.
//
//  Fan control client for the FanCurve agent. Delegates to the upstream
//  `SMCFanXPCClient` from macos-smc-fan. Priority arbitration is handled
//  by the privileged helper directly; there is no intermediate daemon.
//  This wrapper preserves the GUI facing API (`readAndApply`, `shutdown`,
//  `ConnectionState` publisher) so `AgentController` does not change
//  shape.
//

import AppLog
import Combine
import Foundation
import SMCFanProtocol
import SMCFanXPCClient

private let log = AppLog.make(category: "XPCClient")

private enum XPCClientConstants {
  static let maxPlausibleTemperatureC: Float = 150
}

enum XPCClientError: LocalizedError {
  case unavailable(String)

  var errorDescription: String? {
    switch self {
    case .unavailable(let message):
      return message
    }
  }
}

/// Upstream's FanInfo and the project local FanInfo in
/// Sources/Common/SMCProtocol.swift have the same fields but are distinct
/// types. Convert at the XPC boundary so AgentController keeps using the
/// local type.
private typealias UpstreamFanInfo = SMCFanProtocol.FanInfo

private func toLocal(_ up: UpstreamFanInfo) -> FanInfo {
  FanInfo(
    actualRPM: up.actualRPM,
    targetRPM: up.targetRPM,
    minRPM: up.minRPM,
    maxRPM: up.maxRPM,
    manualMode: up.manualMode
  )
}

enum ConnectionState: Sendable {
  case connected
  case disconnected
  case error(String)
}

// MARK: - XPCClient

/// Thin wrapper around `SMCFanXPCClient` that preserves the `@Published`
/// connection state used by the GUI. All XPC reliability (invalidation,
/// reconnect, `ResumeGuard`) is handled by `SMCFanXPCClient` internally,
/// and the privileged helper arbitrates priority.
final class XPCClient: ObservableObject, FanHardware, @unchecked Sendable {
  private let client: SMCFanXPCClient?
  private let initializationError: String?
  private let stateLock = NSLock()

  @Published var state: ConnectionState = .disconnected

  init(
    clientName: String = generatedAppBundleID,
    defaultPriority: Int = SMCFanPriority.curveNormal
  ) {
    do {
      self.client = try SMCFanXPCClient(
        clientName: clientName,
        defaultPriority: defaultPriority
      )
      self.initializationError = nil
    } catch {
      self.client = nil
      self.initializationError = error.localizedDescription
      log.error(
        "xpc.client_init_failed error=\(error.localizedDescription, privacy: .public)")
    }
    log.debug(
      "xpc.client_init name=\(clientName, privacy: .public) default_priority=\(defaultPriority, privacy: .public)"
    )
  }

  /// Invalidate on app termination.
  func shutdown() {
    client?.shutdown()
    Task { @MainActor [weak self] in self?.state = .disconnected }
    log.debug("xpc.shutdown")
  }

  // MARK: - SMC Operations

  func getFanInfo(_ index: UInt) async throws -> FanInfo {
    do {
      let xpcClient = try requireClient()
      let info = try await xpcClient.getFanInfo(index)
      self.markConnected()
      return toLocal(info)
    } catch {
      self.markError(error)
      log.notice(
        "xpc.get_fan_info.failed fan=\(index, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=propagate"
      )
      throw error
    }
  }

  func setFanRPM(_ index: UInt, rpm: Float, priority: Int?) async throws {
    do {
      let xpcClient = try requireClient()
      if let priority {
        try await xpcClient.setFanRPM(index, rpm: rpm, priority: priority)
      } else {
        try await xpcClient.setFanRPM(index, rpm: rpm)
      }
      self.markConnected()
    } catch let err as SMCXPCConflictError {
      // Preempted by a higher priority client (for example lmd while an
      // LLM is running). Not an error from the curve's point of view;
      // skip this write and let the next tick retry.
      self.markConnected()
      log.notice(
        "xpc.write_preempted fan=\(index, privacy: .public) reason=\(err.message, privacy: .public)"
      )
      return
    } catch {
      self.markError(error)
      log.notice(
        "xpc.set_fan_rpm.failed fan=\(index, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=propagate"
      )
      throw error
    }
  }

  func setFanAuto(_ index: UInt, priority: Int?) async throws {
    do {
      let xpcClient = try requireClient()
      if let priority {
        try await xpcClient.setFanAuto(index, priority: priority)
      } else {
        try await xpcClient.setFanAuto(index)
      }
      self.markConnected()
    } catch let err as SMCXPCConflictError {
      self.markConnected()
      log.notice(
        "xpc.auto_preempted fan=\(index, privacy: .public) reason=\(err.message, privacy: .public)"
      )
      return
    } catch {
      self.markError(error)
      log.notice(
        "xpc.set_fan_auto.failed fan=\(index, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=propagate"
      )
      throw error
    }
  }

  func readKey(_ key: String) async throws -> Float {
    do {
      let xpcClient = try requireClient()
      let value = try await xpcClient.readKey(key)
      self.markConnected()
      return value
    } catch {
      self.markError(error)
      log.notice(
        "xpc.read_key.failed key=\(key, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=propagate"
      )
      throw error
    }
  }

  func getOwnership() async throws -> [AgentOwnershipEntry] {
    do {
      let xpcClient = try requireClient()
      let entries = try await xpcClient.getOwnership()
      self.markConnected()
      return entries.map { entry in
        AgentOwnershipEntry(
          id: entry.fanIndex,
          fanIndex: entry.fanIndex,
          clientName: entry.clientName,
          priority: entry.priority,
          ageSeconds: entry.secondsSinceLastWrite
        )
      }
    } catch {
      self.markError(error)
      log.notice(
        "xpc.get_ownership.failed error=\(error.localizedDescription, privacy: .public) recovery=propagate"
      )
      throw error
    }
  }

  // MARK: - Batched read + apply

  func readAndApply(
    fanCount: UInt,
    tempKeys: [String],
    setFans: [(index: UInt, rpm: Float)] = [],
    autoFans: [UInt] = [],
    priority: Int? = nil
  ) async -> FanHardwareBatchRead {
    var fans: [FanInfo] = []
    if fanCount > 0 {
      for fanIndex in 0..<fanCount {
        do {
          let info = try await self.getFanInfo(fanIndex)
          fans.append(info)
        } catch {
          log.notice(
            "xpc.batch.fan_read_failed fan=\(fanIndex, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=skip-fan"
          )
        }
      }
    }

    var temps: [String: Float] = [:]
    for key in tempKeys {
      do {
        let value = try await self.readKey(key)
        if value > 0, value < XPCClientConstants.maxPlausibleTemperatureC {
          temps[key] = value
        }
      } catch {
        log.notice(
          "xpc.batch.temp_read_failed key=\(key, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=skip-temperature"
        )
      }
    }

    for fanTarget in setFans {
      do {
        try await self.setFanRPM(fanTarget.index, rpm: fanTarget.rpm, priority: priority)
      } catch {
        log.notice(
          "xpc.batch.fan_write_failed fan=\(fanTarget.index, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=continue-batch"
        )
      }
    }
    for fanIndex in autoFans {
      do {
        try await self.setFanAuto(fanIndex, priority: priority)
      } catch {
        log.notice(
          "xpc.batch.auto_write_failed fan=\(fanIndex, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=continue-batch"
        )
      }
    }

    return FanHardwareBatchRead(fans: fans, temps: temps)
  }

  // MARK: - State transitions

  private func requireClient() throws -> SMCFanXPCClient {
    if let client {
      return client
    }

    let message = initializationError ?? "SMCFanXPCClient is unavailable"
    log.notice(
      "xpc.client_unavailable error=\(message, privacy: .public) recovery=propagate"
    )
    throw XPCClientError.unavailable(message)
  }

  private func markConnected() {
    self.stateLock.lock()
    let wasConnected: Bool
    if case .connected = self.state { wasConnected = true } else { wasConnected = false }
    self.stateLock.unlock()
    if !wasConnected {
      Task { @MainActor [weak self] in self?.state = .connected }
    }
  }

  private func markError(_ error: Error) {
    let msg = error.localizedDescription
    Task { @MainActor [weak self] in self?.state = .error(msg) }
  }
}
