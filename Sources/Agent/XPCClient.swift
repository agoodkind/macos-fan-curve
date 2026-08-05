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
  static let legacyProbeTimeoutSeconds: TimeInterval = 5
  static let maxPlausibleTemperatureC: Float = 150
}

// MARK: - SMCKeyAbsence

/// A missing SMC key is a definite answer, not a transport failure. The
/// helper's `smcReadKey` reply carries `SMCError.firmware(.notFound)`'s
/// description as a plain string across the XPC boundary, wrapped in
/// `SMCXPCError`; this substring match is the only signal available here
/// for "the SMC firmware says this key does not exist."
private enum SMCKeyAbsence {
  static let notFoundMarker = "notFound (0x84)"

  static func isDefiniteKeyAbsence(_ error: Error) -> Bool {
    guard let xpcError = error as? SMCXPCError else { return false }
    return xpcError.message.contains(notFoundMarker)
  }
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
private typealias UpstreamHelperIdentity = SMCFanProtocol.SMCFanHelperIdentity

private func toLocal(_ up: UpstreamFanInfo) -> FanInfo {
  FanInfo(
    actualRPM: up.actualRPM,
    targetRPM: up.targetRPM,
    minRPM: up.minRPM,
    maxRPM: up.maxRPM,
    manualMode: up.manualMode
  )
}

private func toLocal(_ identity: UpstreamHelperIdentity) -> SystemHelperIdentity {
  SystemHelperIdentity(
    version: identity.version,
    build: identity.build,
    commit: identity.commit,
    executableHash: identity.executableHash,
    protocolVersion: identity.protocolVersion
  )
}

enum ConnectionState: Sendable {
  case connected
  case disconnected
  case error(String)
}

// MARK: - XPCClient

/// Thin wrapper around `SMCFanXPCClient` that preserves the `@Published`
/// connection state used by the GUI. The upstream client handles routine
/// reconnects and reply safety. Lifecycle operations use isolated request
/// scopes so cancellation preserves normal fan control. The privileged helper
/// arbitrates priority.
final class XPCClient: ObservableObject, FanHardware, @unchecked Sendable {
  private let client: SMCFanXPCClient?
  private let initializationError: String?
  private let legacyProbeTimeoutSeconds: TimeInterval
  let lifecycleRequestDispatchGate: @Sendable () async -> Void
  private let stateLock = NSLock()

  @Published var state: ConnectionState = .disconnected

  init(
    clientName: String = generatedAppBundleID,
    defaultPriority: Int = SMCFanPriority.curveNormal
  ) {
    self.client = SMCFanXPCClient(
      clientName: clientName,
      defaultPriority: defaultPriority
    )
    self.initializationError = nil
    self.legacyProbeTimeoutSeconds =
      XPCClientConstants.legacyProbeTimeoutSeconds
    self.lifecycleRequestDispatchGate = {
      // Production lifecycle requests dispatch immediately.
    }
    log.debug(
      "xpc.client_init name=\(clientName, privacy: .public) default_priority=\(defaultPriority, privacy: .public)"
    )
  }

  init(
    upstreamClient: SMCFanXPCClient,
    legacyProbeTimeoutSeconds: TimeInterval =
      XPCClientConstants.legacyProbeTimeoutSeconds,
    lifecycleRequestDispatchGate: @escaping @Sendable () async -> Void = {
      // Injected lifecycle requests dispatch immediately unless tests provide a gate.
    }
  ) {
    self.client = upstreamClient
    self.initializationError = nil
    self.legacyProbeTimeoutSeconds = legacyProbeTimeoutSeconds
    self.lifecycleRequestDispatchGate = lifecycleRequestDispatchGate
    log.debug("xpc.client_init source=injected-upstream")
  }

  /// Invalidate on app termination.
  func shutdown() {
    client?.shutdown()
    Task { @MainActor [weak self] in self?.state = .disconnected }
    log.debug("xpc.shutdown")
  }

  // MARK: - SMC Operations
}

// MARK: - XPCClient

extension XPCClient {
  func getHelperIdentity() async throws -> SystemHelperIdentity {
    do {
      let xpcClient = try requireClient()
      let identity = try await xpcClient.getHelperIdentity()
      self.markConnected()
      log.info(
        "xpc.helper_identity.completed version=\(identity.version, privacy: .public) build=\(identity.build, privacy: .public) protocol=\(identity.protocolVersion, privacy: .public) hash=\(BuildFingerprint.presented(identity.executableHash), privacy: .public)"
      )
      return toLocal(identity)
    } catch {
      self.markError(error)
      log.notice(
        "xpc.helper_identity.failed error=\(error.localizedDescription, privacy: .public) recovery=propagate"
      )
      throw error
    }
  }

  func probeLegacyHelperReachability() async throws {
    let xpcClient = try requireClient()
    let completion = XPCProbeCompletion()
    log.notice(
      "xpc.legacy_probe.started timeoutSeconds=\(legacyProbeTimeoutSeconds, privacy: .public)"
    )
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        completion.install(continuation)
        let operationTask = Task {
          switch await performLegacyProbe(xpcClient) {
          case .success:
            completion.finish(with: .success(()))
          case .failure(let error):
            guard completion.finish(with: .failure(error)) else { return }
            log.notice(
              "xpc.legacy_probe.failed error=\(error.localizedDescription, privacy: .public) recovery=return-error"
            )
          }
        }
        let timeoutTask = Task {
          do {
            try await ContinuousClock().sleep(
              for: .seconds(legacyProbeTimeoutSeconds)
            )
          } catch {
            log.notice(
              "xpc.legacy_probe.timeout_cancelled recovery=stop-deadline"
            )
            return
          }
          let timeoutError = SMCXPCTimeoutError(
            label: "legacyHelperProbe",
            seconds: legacyProbeTimeoutSeconds
          )
          if completion.finish(with: .failure(timeoutError)) {
            log.notice(
              "xpc.legacy_probe.failed error=timeout timeoutSeconds=\(legacyProbeTimeoutSeconds, privacy: .public) recovery=cancel-operation-task"
            )
          }
        }
        completion.installTasks(
          operationTask: operationTask,
          timeoutTask: timeoutTask
        )
      }
    } onCancel: {
      if completion.finish(with: .failure(CancellationError())) {
        log.notice(
          "xpc.legacy_probe.cancelled recovery=cancel-operation-task"
        )
      }
    }
    self.markConnected()
    log.notice("xpc.legacy_probe.completed result=reachable")
  }

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
      // A definite "no such key" answer is not a transport failure: do not
      // flip ConnectionState to .error for it. Real transport failures
      // (helper down, restarting, unreachable) still mark the connection.
      if SMCKeyAbsence.isDefiniteKeyAbsence(error) {
        log.notice(
          "xpc.read_key.failed key=\(key, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=propagate-key-absent"
        )
      } else {
        self.markError(error)
        log.notice(
          "xpc.read_key.failed key=\(key, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=propagate"
        )
      }
      throw error
    }
  }

  /// Reads every key in one round trip instead of one per key. A tick's
  /// temperature read is the bulk of its cost, and each round trip stretches
  /// from milliseconds to seconds when the machine is loaded, so reading N
  /// keys serially is what let a tick run for half a minute.
  ///
  /// Returns the keys that answered with a usable value. A key the hardware
  /// does not have is a per-key answer, not a transport failure, so it is
  /// dropped without marking the connection errored. A throw means the round
  /// trip itself failed, and the caller falls back to per-key reads.
  func readKeys(_ keys: [String]) async throws -> [String: Float] {
    let xpcClient = try requireClient()
    log.debug("xpc.read_keys.started requested=\(keys.count, privacy: .public)")
    do {
      let results = try await xpcClient.readKeys(keys)
      self.markConnected()

      var values: [String: Float] = [:]
      var absentCount = 0
      for result in results {
        guard result.success else {
          absentCount += 1
          continue
        }
        values[result.key] = result.value
      }
      log.debug(
        "xpc.read_keys.completed requested=\(keys.count, privacy: .public) returned=\(values.count, privacy: .public) absent=\(absentCount, privacy: .public)"
      )
      return values
    } catch {
      self.markError(error)
      log.notice(
        "xpc.read_keys.failed count=\(keys.count, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=propagate"
      )
      throw error
    }
  }

  /// Asks the SMC what keys it actually has. Returns an empty array on any
  /// failure, matching upstream `SMCFanXPCClient.enumerateKeys()`'s
  /// contract: an empty result means "could not enumerate," not "this
  /// machine has no keys." Callers must not treat it as a pruning signal.
  func enumerateKeys() async -> [String] {
    do {
      let xpcClient = try requireClient()
      let keys = await xpcClient.enumerateKeys()
      if !keys.isEmpty {
        self.markConnected()
      }
      log.debug("xpc.enumerate_keys.completed count=\(keys.count, privacy: .public)")
      return keys
    } catch {
      self.markError(error)
      log.notice(
        "xpc.enumerate_keys.failed error=\(error.localizedDescription, privacy: .public) recovery=empty-result"
      )
      return []
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

  /// Reads every temperature key in one round trip, keeping only plausible
  /// readings. A key the hardware lacks, or one reporting an implausible
  /// value, is simply absent from the result.
  ///
  /// Falls back to per-key reads when the round trip itself fails, rather
  /// than returning nothing and letting the tick drive the curve from a zero
  /// temperature.
  private func readTemperatures(_ tempKeys: [String]) async -> [String: Float] {
    guard !tempKeys.isEmpty else { return [:] }

    do {
      let values = try await self.readKeys(tempKeys)
      let accepted = values.filter { Self.isPlausibleTemperature($0.value) }
      // Counts only. The key names are already logged once at startup by
      // sensor resolution, and repeating them every tick is what produced
      // tens of thousands of log lines an hour before.
      log.debug(
        "xpc.batch.temps_read requested=\(tempKeys.count, privacy: .public) accepted=\(accepted.count, privacy: .public) rejected=\(tempKeys.count - accepted.count, privacy: .public) source=batch"
      )
      return accepted
    } catch {
      log.notice(
        "xpc.batch.temp_batch_failed count=\(tempKeys.count, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=per-key-reads"
      )
      return await readTemperaturesPerKey(tempKeys)
    }
  }

  /// One round trip per key. Only reached when the batched read failed
  /// outright, so the cost is acceptable against reading no temperature.
  private func readTemperaturesPerKey(_ tempKeys: [String]) async -> [String: Float] {
    var temps: [String: Float] = [:]
    for key in tempKeys {
      do {
        let value = try await self.readKey(key)
        if Self.isPlausibleTemperature(value) {
          temps[key] = value
        }
      } catch {
        log.notice(
          "xpc.batch.temp_read_failed key=\(key, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=skip-temperature"
        )
      }
    }
    // Notice rather than debug: reaching this path at all means the batched
    // read failed, so how much the fallback salvaged is worth having without
    // turning debug logging on.
    log.notice(
      "xpc.batch.temps_read requested=\(tempKeys.count, privacy: .public) accepted=\(temps.count, privacy: .public) rejected=\(tempKeys.count - temps.count, privacy: .public) source=per-key-fallback"
    )
    return temps
  }

  /// A reading outside this range is a sensor the machine answered for but
  /// cannot be a real temperature, so it must not reach the curve.
  private static func isPlausibleTemperature(_ value: Float) -> Bool {
    value > 0 && value < XPCClientConstants.maxPlausibleTemperatureC
  }

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

    let temps = await readTemperatures(tempKeys)

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

  func requireClient() throws -> SMCFanXPCClient {
    if let client {
      return client
    }

    let message = initializationError ?? "SMCFanXPCClient is unavailable"
    log.notice(
      "xpc.client_unavailable error=\(message, privacy: .public) recovery=propagate"
    )
    throw XPCClientError.unavailable(message)
  }

  private static func requestLegacyProbe(
    _ client: SMCFanXPCClient,
    scope: SMCFanXPCRequestScope
  ) async -> Result<Void, Error> {
    do {
      try Task.checkCancellation()
      _ = try await client.getFanCount(scope: scope)
      return .success(())
    } catch {
      log.notice(
        "xpc.legacy_probe.request_failed error=\(error.localizedDescription, privacy: .public) recovery=resolve-race"
      )
      return .failure(error)
    }
  }

  private func performLegacyProbe(
    _ client: SMCFanXPCClient
  ) async -> Result<Void, Error> {
    await lifecycleRequestDispatchGate()
    do {
      try Task.checkCancellation()
      let scope = client.makeRequestScope()
      return await Self.requestLegacyProbe(client, scope: scope)
    } catch {
      log.notice(
        "xpc.legacy_probe.request_cancelled recovery=skip-request"
      )
      return .failure(error)
    }
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
