//
//  XPCClient.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
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

/// Thin wrapper around `SMCFanXPCClient` that preserves the `@Published`
/// connection state used by the GUI. All XPC reliability (invalidation,
/// reconnect, `ResumeGuard`) is handled by `SMCFanXPCClient` internally,
/// and the privileged helper arbitrates priority.
class XPCClient: ObservableObject, @unchecked Sendable {
    private let client: SMCFanXPCClient
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
        } catch {
            log.error("xpc.client_init_failed error=\(error.localizedDescription, privacy: .public)")
            preconditionFailure("SMCFanXPCClient init failed: \(error.localizedDescription)")
        }
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
            log.notice(
                "xpc.get_fan_count.failed error=\(error.localizedDescription, privacy: .public) recovery=propagate"
            )
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
            log.notice(
                "xpc.get_fan_info.failed fan=\(index, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=propagate"
            )
            throw error
        }
    }

    func setFanRPM(_ index: UInt, rpm: Float) async throws {
        try await self.setFanRPM(index, rpm: rpm, priority: nil)
    }

    func setFanRPM(_ index: UInt, rpm: Float, priority: Int?) async throws {
        do {
            if let priority {
                try await client.setFanRPM(index, rpm: rpm, priority: priority)
            } else {
                try await client.setFanRPM(index, rpm: rpm)
            }
            self.markConnected()
        } catch let err as SMCXPCConflictError {
            // Preempted by a higher priority client (for example lmd while an
            // LLM is running). Not an error from the curve's point of view;
            // skip this write and let the next tick retry.
            log.debug(
                "xpc.write_preempted fan=\(index, privacy: .public) reason=\(err.message, privacy: .public)"
            )
        } catch {
            self.markError(error)
            log.notice(
                "xpc.set_fan_rpm.failed fan=\(index, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=propagate"
            )
            throw error
        }
    }

    func setFanAuto(_ index: UInt) async throws {
        try await self.setFanAuto(index, priority: nil)
    }

    func setFanAuto(_ index: UInt, priority: Int?) async throws {
        do {
            if let priority {
                try await client.setFanAuto(index, priority: priority)
            } else {
                try await client.setFanAuto(index)
            }
            self.markConnected()
        } catch let err as SMCXPCConflictError {
            log.debug(
                "xpc.auto_preempted fan=\(index, privacy: .public) reason=\(err.message, privacy: .public)"
            )
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
            let value = try await client.readKey(key)
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

    // MARK: - Batched read + apply

    struct BatchReadResult: Sendable {
        let fans: [FanInfo]
        let temps: [String: Float]
    }

    func readAndApply(
        fanCount: UInt,
        tempKeys: [String],
        setFans: [(index: UInt, rpm: Float)] = [],
        autoFans: [UInt] = [],
        priority: Int? = nil
    ) async -> BatchReadResult {
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
                if value > 0, value < 150 {
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
