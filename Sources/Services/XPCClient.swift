//
//  XPCClient.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//
//  Fan control client for the FanCurve agent. Delegates to `SMCDClient`
//  from macos-smc-fan so arbitration is handled by the shared user space
//  smcd daemon. This wrapper preserves the previous API (`readAndApply`,
//  `shutdown`, `ConnectionState` publisher) so `AgentController` does not
//  have to change.
//

import AppLog
import Combine
import Foundation
import SMCDClient
import SMCFanProtocol

private let log = AppLog.make(category: "XPCClient")

/// Upstream's FanInfo has the same fields as the project local one defined
/// in Sources/Common/SMCProtocol.swift. They are distinct types. Convert
/// at the XPC boundary so AgentController continues to use the local type.
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
  case disconnected
  case connected
  case error(String)
}

/// Thin wrapper around `SMCDClient` that preserves the @Published
/// connection state used by the GUI. All XPC reliability (invalidation,
/// reconnect, `ResumeGuard`) is handled by `SMCDClient` internally.
class XPCClient: ObservableObject, @unchecked Sendable {
  private let client: SMCDClient
  private let stateLock = NSLock()

  @Published var state: ConnectionState = .disconnected

  init(
    clientName: String = "fancurve",
    defaultPriority: Int = SMCDPriority.curveNormal
  ) {
    self.client = SMCDClient(
      clientName: clientName,
      defaultPriority: defaultPriority
    )
    log.debug(
      "xpc.client_init name=\(clientName, privacy: .public) default_priority=\(defaultPriority, privacy: .public)"
    )
  }

  /// Invalidate on app termination.
  func shutdown() {
    self.client.shutdown()
    Task { @MainActor [weak self] in self?.state = .disconnected }
    log.debug("xpc.shutdown")
  }

  // MARK: - SMC Operations

  func getFanCount() async throws -> UInt {
    do {
      let count = try await client.getFanCount()
      self.markConnected()
      return count
    } catch {
      self.markError(error)
      throw error
    }
  }

  func getFanInfo(_ index: UInt) async throws -> FanInfo {
    do {
      let info = try await client.getFanInfo(index)
      self.markConnected()
      return toLocal(info)
    } catch {
      self.markError(error)
      throw error
    }
  }

  func setFanRPM(_ index: UInt, rpm: Float) async throws {
    try await self.setFanRPM(index, rpm: rpm, priority: nil)
  }

  func setFanRPM(_ index: UInt, rpm: Float, priority: Int?) async throws {
    do {
      if let priority = priority {
        try await client.setFanRPM(index, rpm: rpm, priority: priority)
      } else {
        try await client.setFanRPM(index, rpm: rpm)
      }
      self.markConnected()
    } catch let err as SMCDConflictError {
      // Preempted by a higher priority client (for example lmd while an
      // LLM is running). Not an error from the curve's point of view;
      // skip this write and let the next tick retry.
      log.debug(
        "xpc.write_preempted fan=\(index, privacy: .public) reason=\(err.message, privacy: .public)"
      )
    } catch {
      self.markError(error)
      throw error
    }
  }

  func setFanAuto(_ index: UInt) async throws {
    try await self.setFanAuto(index, priority: nil)
  }

  func setFanAuto(_ index: UInt, priority: Int?) async throws {
    do {
      if let priority = priority {
        try await client.setFanAuto(index, priority: priority)
      } else {
        try await client.setFanAuto(index)
      }
      self.markConnected()
    } catch let err as SMCDConflictError {
      log.debug(
        "xpc.auto_preempted fan=\(index, privacy: .public) reason=\(err.message, privacy: .public)"
      )
    } catch {
      self.markError(error)
      throw error
    }
  }

  func readKey(_ key: String) async throws -> Float {
    do {
      let v = try await client.readKey(key)
      self.markConnected()
      return v
    } catch {
      self.markError(error)
      throw error
    }
  }

  // MARK: - Batched read + apply

  struct BatchReadResult: Sendable {
    let fans: [FanInfo]
    let temps: [String: Float]
  }

  func readAndApply(
    fanCount: UInt,
    tempKeys: [String],
    setFans: [(index: UInt, rpm: Float)]?,
    autoFans: [UInt]?,
    priority: Int? = nil
  ) async throws -> BatchReadResult {
    var fans: [FanInfo] = []
    if fanCount > 0 {
      for i in 0..<fanCount {
        if let info = try? await self.getFanInfo(i) { fans.append(info) }
      }
    }

    var temps: [String: Float] = [:]
    for key in tempKeys {
      if let value = try? await self.readKey(key), value > 0, value < 150 {
        temps[key] = value
      }
    }

    if let setFans {
      for f in setFans {
        try? await self.setFanRPM(f.index, rpm: f.rpm, priority: priority)
      }
    }
    if let autoFans {
      for i in autoFans {
        try? await self.setFanAuto(i, priority: priority)
      }
    }

    return BatchReadResult(fans: fans, temps: temps)
  }

  // MARK: - State transitions

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
