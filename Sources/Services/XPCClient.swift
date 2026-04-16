//
//  XPCClient.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

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

class XPCClient: ObservableObject, @unchecked Sendable {
  private var connection: NSXPCConnection?
  private var proxy: SMCFanHelperProtocol?

  @Published var state: ConnectionState = .disconnected

  func connect() {
    let config = SMCFanConfiguration.default
    Log.debug("connecting to XPC service \(config.helperBundleID)")

    let conn = NSXPCConnection(
      machServiceName: config.helperBundleID,
      options: .privileged
    )
    conn.remoteObjectInterface = NSXPCInterface(with: SMCFanHelperProtocol.self)
    conn.invalidationHandler = { [weak self] in
      Task { @MainActor in self?.state = .disconnected }
    }
    conn.interruptionHandler = { [weak self] in
      Task { @MainActor in self?.state = .error("Connection interrupted") }
    }
    conn.resume()

    guard
      let p = conn.remoteObjectProxyWithErrorHandler({ [weak self] error in
        Task { @MainActor in self?.state = .error(error.localizedDescription) }
      }) as? SMCFanHelperProtocol
    else {
      state = .error("Failed to create XPC proxy")
      return
    }

    connection = conn
    proxy = p
    state = .connected
    Log.debug("XPC connection established")
  }

  func disconnect() {
    connection?.invalidate()
    connection = nil
    proxy = nil
    state = .disconnected
  }

  // MARK: - SMC Operations

  func open() async throws {
    guard let proxy else { throw SMCXPCError("Not connected") }
    try await callVoid { proxy.smcOpen(reply: $0) }
  }

  func getFanCount() async throws -> UInt {
    guard let proxy else { throw SMCXPCError("Not connected") }
    return try await call { proxy.smcGetFanCount(reply: $0) }
  }

  func getFanInfo(_ index: UInt) async throws -> FanInfo {
    guard let proxy else { throw SMCXPCError("Not connected") }
    return try await withCheckedThrowingContinuation { continuation in
      proxy.smcGetFanInfo(index) { success, actual, target, min, max, manual, error in
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
    guard let proxy else { throw SMCXPCError("Not connected") }
    try await callVoid { proxy.smcSetFanRPM(index, rpm: rpm, reply: $0) }
  }

  func setFanAuto(_ index: UInt) async throws {
    guard let proxy else { throw SMCXPCError("Not connected") }
    try await callVoid { proxy.smcSetFanAuto(index, reply: $0) }
  }

  func readKey(_ key: String) async throws -> Float {
    guard let proxy else { throw SMCXPCError("Not connected") }
    return try await call { proxy.smcReadKey(key, reply: $0) }
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
