//
//  XPCClient.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import AppLog
import Combine
import Foundation

private let log = AppLog.make(category: "XPCClient")

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
///
/// Every remote call uses a per-call proxy created via
/// `remoteObjectProxyWithErrorHandler`. The error handler resumes the
/// awaiting continuation on XPC failure so we never leak continuations
/// or their captured state. Leaked continuations were causing the
/// agent's memory to balloon over hours of uptime.
///
/// interruptionHandler: log only (auto-reconnects on next message).
/// invalidationHandler: nil out, recreate lazily on next use.
class XPCClient: ObservableObject, @unchecked Sendable {
  private var connection: NSXPCConnection?
  private let lock = NSLock()
  private let helperBundleID: String
  private var smcOpened = false

  @Published var state: ConnectionState = .disconnected

  init() {
    self.helperBundleID = SMCFanConfiguration.default.helperBundleID
  }

  /// Returns the cached NSXPCConnection, creating it lazily. The
  /// per-call proxy is obtained separately so each call can install
  /// its own error handler.
  private func ensureConnection() throws -> NSXPCConnection {
    lock.lock()
    defer { lock.unlock() }

    if let c = connection { return c }

    let conn = NSXPCConnection(
      machServiceName: helperBundleID,
      options: .privileged)
    conn.remoteObjectInterface = NSXPCInterface(with: SMCFanHelperProtocol.self)

    conn.interruptionHandler = { [weak self] in
      log.debug("xpc.interrupted action=auto-reconnect-on-next-message")
      Task { @MainActor in self?.state = .disconnected }
    }
    conn.invalidationHandler = { [weak self] in
      log.debug("xpc.invalidated action=recreate-on-next-use")
      self?.lock.lock()
      self?.connection = nil
      self?.smcOpened = false
      self?.lock.unlock()
      Task { @MainActor in self?.state = .disconnected }
    }

    conn.resume()
    connection = conn
    Task { @MainActor in state = .connected }
    return conn
  }

  /// Open the SMC connection in the helper. Idempotent.
  func ensureOpen() async throws {
    if smcOpened { return }
    try await callVoid { proxy, reply in proxy.smcOpen(reply: reply) }
    smcOpened = true
  }

  /// Invalidate on app termination.
  func shutdown() {
    lock.lock()
    connection?.invalidate()
    connection = nil
    lock.unlock()
  }

  // MARK: - SMC Operations

  func getFanCount() async throws -> UInt {
    try await ensureOpen()
    return try await call { proxy, reply in proxy.smcGetFanCount(reply: reply) }
  }

  func getFanInfo(_ index: UInt) async throws -> FanInfo {
    try await ensureOpen()
    let conn = try ensureConnection()
    return try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<FanInfo, Error>) in
      let once = ResumeGuard()
      let proxy = conn.remoteObjectProxyWithErrorHandler { error in
        once.tryResume {
          continuation.resume(throwing: SMCXPCError(error.localizedDescription))
        }
      }
      guard let p = proxy as? SMCFanHelperProtocol else {
        once.tryResume {
          continuation.resume(throwing: SMCXPCError("Failed to get proxy"))
        }
        return
      }
      p.smcGetFanInfo(index) { success, actual, target, min, max, manual, error in
        once.tryResume {
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
  }

  func setFanRPM(_ index: UInt, rpm: Float) async throws {
    try await ensureOpen()
    try await callVoid { proxy, reply in
      proxy.smcSetFanRPM(index, rpm: rpm, reply: reply)
    }
  }

  func setFanAuto(_ index: UInt) async throws {
    try await ensureOpen()
    try await callVoid { proxy, reply in proxy.smcSetFanAuto(index, reply: reply) }
  }

  func readKey(_ key: String) async throws -> Float {
    try await ensureOpen()
    return try await call { proxy, reply in proxy.smcReadKey(key, reply: reply) }
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
    autoFans: [UInt]?
  ) async throws -> BatchReadResult {
    try await ensureOpen()

    var fans: [FanInfo] = []
    if fanCount > 0 {
      for i in 0..<fanCount {
        if let info = try? await getFanInfo(i) { fans.append(info) }
      }
    }

    var temps: [String: Float] = [:]
    for key in tempKeys {
      if let value = try? await readKey(key), value > 0, value < 150 {
        temps[key] = value
      }
    }

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

  /// Wraps a proxy call whose reply signature is `(Bool, T, String?)`.
  /// The per-call error handler guarantees the continuation resumes even
  /// when the XPC connection dies before the reply fires, preventing
  /// continuation leaks.
  private func call<T: Sendable>(
    _ block: @escaping (
      SMCFanHelperProtocol,
      @escaping @Sendable (Bool, T, String?) -> Void
    ) -> Void
  ) async throws -> T {
    let conn = try ensureConnection()
    return try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<T, Error>) in
      let once = ResumeGuard()
      let proxy = conn.remoteObjectProxyWithErrorHandler { error in
        once.tryResume {
          continuation.resume(throwing: SMCXPCError(error.localizedDescription))
        }
      }
      guard let p = proxy as? SMCFanHelperProtocol else {
        once.tryResume {
          continuation.resume(throwing: SMCXPCError("Failed to get proxy"))
        }
        return
      }
      block(p) { success, value, error in
        once.tryResume {
          if success { continuation.resume(returning: value) }
          else { continuation.resume(throwing: SMCXPCError(error)) }
        }
      }
    }
  }

  /// Same idea as `call` but for replies of `(Bool, String?)`.
  private func callVoid(
    _ block: @escaping (
      SMCFanHelperProtocol,
      @escaping @Sendable (Bool, String?) -> Void
    ) -> Void
  ) async throws {
    let conn = try ensureConnection()
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      let once = ResumeGuard()
      let proxy = conn.remoteObjectProxyWithErrorHandler { error in
        once.tryResume {
          continuation.resume(throwing: SMCXPCError(error.localizedDescription))
        }
      }
      guard let p = proxy as? SMCFanHelperProtocol else {
        once.tryResume {
          continuation.resume(throwing: SMCXPCError("Failed to get proxy"))
        }
        return
      }
      block(p) { success, error in
        once.tryResume {
          if success { continuation.resume() }
          else { continuation.resume(throwing: SMCXPCError(error)) }
        }
      }
    }
  }
}

/// Single-use gate ensuring a closure runs exactly once. We need this
/// because both the XPC reply and the XPC error handler can fire, and
/// a continuation must only be resumed a single time.
private final class ResumeGuard: @unchecked Sendable {
  private var fired = false
  private let lock = NSLock()

  func tryResume(_ action: () -> Void) {
    lock.lock()
    if fired {
      lock.unlock()
      return
    }
    fired = true
    lock.unlock()
    action()
  }
}
