//
//  XPCClient.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import Combine
import Foundation

enum ConnectionState: Sendable {
  case disconnected
  case connected
  case error(String)
}

struct SMCXPCError: LocalizedError, Sendable {
  let message: String
  var errorDescription: String? { message }
  init(_ message: String?) { self.message = message ?? "Unknown error" }
}

/// Apple-idiomatic XPC client. One persistent connection per app lifetime.
/// interruptionHandler: log only (auto-reconnects on next message).
/// invalidationHandler: nil out, recreate lazily on next use.
/// Per Apple WWDC 2012 Session 241 and NSXPCConnection documentation.
class XPCClient: ObservableObject, @unchecked Sendable {
  private var connection: NSXPCConnection?
  private var cachedProxy: SMCFanHelperProtocol?
  private let lock = NSLock()
  private let helperBundleID: String
  private var smcOpened = false

  @Published var state: ConnectionState = .disconnected

  init() {
    self.helperBundleID = SMCFanConfiguration.default.helperBundleID
  }

  /// Returns the XPC proxy, creating the connection lazily if needed.
  /// Thread-safe. Connection persists for app lifetime.
  func proxy() throws -> SMCFanHelperProtocol {
    lock.lock()
    defer { lock.unlock() }

    if let p = cachedProxy { return p }

    let conn = NSXPCConnection(
      machServiceName: helperBundleID,
      options: .privileged
    )
    conn.remoteObjectInterface = NSXPCInterface(with: SMCFanHelperProtocol.self)

    // interruptionHandler: do NOT touch the connection. It auto-reconnects.
    conn.interruptionHandler = { [weak self] in
      Log.debug("XPC connection interrupted, will auto-reconnect on next message")
      Task { @MainActor in self?.state = .disconnected }
    }

    // invalidationHandler: connection is permanently dead. Nil out for lazy recreation.
    conn.invalidationHandler = { [weak self] in
      Log.debug("XPC connection invalidated, will recreate on next use")
      self?.lock.lock()
      self?.connection = nil
      self?.cachedProxy = nil
      self?.smcOpened = false
      self?.lock.unlock()
      Task { @MainActor in self?.state = .disconnected }
    }

    conn.resume()

    guard
      let p = conn.remoteObjectProxyWithErrorHandler({ error in
        Log.debug("XPC proxy error: \(error.localizedDescription)")
      }) as? SMCFanHelperProtocol
    else {
      throw SMCXPCError("Failed to create XPC proxy. Is the helper installed?")
    }

    connection = conn
    cachedProxy = p
    Task { @MainActor in state = .connected }
    return p
  }

  /// Open the SMC connection in the helper. Idempotent.
  func ensureOpen() async throws {
    if smcOpened { return }
    let p = try proxy()
    try await callVoid { p.smcOpen(reply: $0) }
    smcOpened = true
  }

  /// Invalidate on app termination.
  func shutdown() {
    lock.lock()
    connection?.invalidate()
    connection = nil
    cachedProxy = nil
    lock.unlock()
  }

  // MARK: - SMC Operations

  func getFanCount() async throws -> UInt {
    try await ensureOpen()
    let p = try proxy()
    return try await call { p.smcGetFanCount(reply: $0) }
  }

  func getFanInfo(_ index: UInt) async throws -> FanInfo {
    try await ensureOpen()
    let p = try proxy()
    return try await withCheckedThrowingContinuation { continuation in
      p.smcGetFanInfo(index) { success, actual, target, min, max, manual, error in
        if success {
          continuation.resume(
            returning: FanInfo(
              actualRPM: actual, targetRPM: target,
              minRPM: min, maxRPM: max, manualMode: manual))
        } else {
          continuation.resume(throwing: SMCXPCError(error))
        }
      }
    }
  }

  func setFanRPM(_ index: UInt, rpm: Float) async throws {
    try await ensureOpen()
    let p = try proxy()
    try await callVoid { p.smcSetFanRPM(index, rpm: rpm, reply: $0) }
  }

  func setFanAuto(_ index: UInt) async throws {
    try await ensureOpen()
    let p = try proxy()
    try await callVoid { p.smcSetFanAuto(index, reply: $0) }
  }

  func readKey(_ key: String) async throws -> Float {
    try await ensureOpen()
    let p = try proxy()
    return try await call { p.smcReadKey(key, reply: $0) }
  }

  // MARK: - Batched read + apply

  /// Result of a batched read.
  struct BatchReadResult: Sendable {
    let fans: [FanInfo]
    let temps: [String: Float]
  }

  /// Performs a batch of operations in sequence on the same connection:
  /// 1. Reads `fanCount` fans (pass 0 to skip)
  /// 2. Reads every key in `tempKeys` (silently skips failures - sensor may not exist)
  /// 3. Applies `setFans` RPM writes
  /// 4. Applies `autoFans` auto-mode writes
  func readAndApply(
    fanCount: UInt,
    tempKeys: [String],
    setFans: [(index: UInt, rpm: Float)]?,
    autoFans: [UInt]?
  ) async throws -> BatchReadResult {
    try await ensureOpen()

    // Fans
    var fans: [FanInfo] = []
    if fanCount > 0 {
      for i in 0..<fanCount {
        if let info = try? await getFanInfo(i) { fans.append(info) }
      }
    }

    // Temps (ignore errors per-key; sensor may not exist on this hardware)
    var temps: [String: Float] = [:]
    for key in tempKeys {
      if let value = try? await readKey(key), value > 0, value < 150 {
        temps[key] = value
      }
    }

    // Writes
    if let setFans {
      for f in setFans {
        try? await setFanRPM(f.index, rpm: f.rpm)
      }
    }
    if let autoFans {
      for i in autoFans {
        try? await setFanAuto(i)
      }
    }

    return BatchReadResult(fans: fans, temps: temps)
  }

  // MARK: - Helpers

  private func call<T: Sendable>(
    _ block: @escaping (@escaping @Sendable (Bool, T, String?) -> Void) -> Void
  ) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      block { success, value, error in
        if success { continuation.resume(returning: value) }
        else { continuation.resume(throwing: SMCXPCError(error)) }
      }
    }
  }

  private func callVoid(
    _ block: @escaping (@escaping @Sendable (Bool, String?) -> Void) -> Void
  ) async throws {
    try await withCheckedThrowingContinuation { continuation in
      block { success, error in
        if success { continuation.resume() }
        else { continuation.resume(throwing: SMCXPCError(error)) }
      }
    }
  }
}
