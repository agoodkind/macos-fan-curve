//
//  InstallationState.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import AppLog
import Combine
import Foundation
import ServiceManagement

private let log = AppLog.make(category: "InstallationState")

/// Tracks whether the privileged helper and background agent are installed
/// and running. Drives the inline onboarding flow in the GUI.
@MainActor
final class InstallationState: ObservableObject {
    enum Step: Equatable {
        case checking
        case helperMissing
        case helperAwaitingApproval
        case agentMissing
        case agentAwaitingApproval
        case ready
    }

    @Published var step: Step = .checking
    @Published var lastError: String?
    @Published var helperReachable: Bool = false
    @Published var agentRawStatus: Int = 0
    /// Timestamp of the Agent's last successful tick, read from the shared
    /// UserDefaults suite on each refresh. 0 when unset.
    @Published var agentLastTickEpoch: Double = 0
    /// Last error string reported by the Agent, empty when the last tick
    /// succeeded or the Agent has never written one.
    @Published var agentLastError: String = ""
    @Published var agentExecutableHash: String = ""

    private var timer: Timer?
    private var lastAutoRefreshAttemptedHash: String?

    /// Convenience computed helpers for the Settings UI.
    var agentEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.Status(rawValue: agentRawStatus) == .enabled
    }

    /// True when the Agent is registered AND has written a tick within the
    /// freshness window. "Registered but silent" means the process died or
    /// is hung, which is what the user sees as "fan control stopped".
    var agentLive: Bool {
        guard agentEnabled else { return false }
        let lastTick = Date(timeIntervalSince1970: agentLastTickEpoch)
        return agentLastTickEpoch > 0 && Date().timeIntervalSince(lastTick) < 10
    }

    var agentStatusLabel: String {
        guard #available(macOS 13.0, *) else { return "Unavailable" }
        switch SMAppService.Status(rawValue: agentRawStatus) {
        case .enabled: return "Enabled"
        case .requiresApproval: return "Awaiting approval in System Settings"
        case .notFound: return "Not installed"
        case .notRegistered: return "Not registered"
        default: return "Unknown"
        }
    }

    func startMonitoring(xpcClient: XPCClient) {
        Task { await refresh(xpcClient: xpcClient) }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if let self {
                    await self.refresh(xpcClient: xpcClient)
                }
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Attempts to register the agent via SMAppService. Idempotent.
    /// Opens System Settings if approval is required.
    func registerAgent() {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.agent(plistName: "\(generatedAgentBundleID).plist")
        do {
            try service.register()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func openLoginItemsSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    /// Unregister the agent. Stops it and removes its entry from Login Items.
    func unregisterAgent() {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.agent(plistName: "\(generatedAgentBundleID).plist")
        do {
            try service.unregister()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Probes current installation status.
    private func refresh(xpcClient: XPCClient) async {
        let helperOK = await helperResponding(xpcClient: xpcClient)
        let agentStatus = currentAgentStatus()

        helperReachable = helperOK
        agentRawStatus = agentStatus.rawValue

        let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
        agentLastTickEpoch = suite.double(forKey: SharedConfigKeys.agentLastTick)
        agentExecutableHash = suite.string(forKey: SharedConfigKeys.agentExecutableHash) ?? ""
        agentLastError = suite.string(forKey: SharedConfigKeys.agentLastError) ?? ""

        if agentStatus == .enabled {
            refreshAgentIfNeeded(runningHash: agentExecutableHash)
        }

        if !helperOK {
            step = .helperMissing
            return
        }

        switch agentStatus {
        case .enabled:
            step = .ready
        case .requiresApproval:
            step = .agentAwaitingApproval
        default:
            step = .agentMissing
        }
    }

    private func helperResponding(xpcClient: XPCClient) async -> Bool {
        do {
            _ = try await xpcClient.getFanCount()
            return true
        } catch {
            return false
        }
    }

    private func currentAgentStatus() -> SMAppService.Status {
        guard #available(macOS 13.0, *) else { return .notFound }
        return SMAppService.agent(plistName: "\(generatedAgentBundleID).plist").status
    }

    private func refreshAgentIfNeeded(runningHash: String) {
        guard #available(macOS 13.0, *) else { return }

        let bundledHash = BuildFingerprint.bundledAgentHash
        guard bundledHash != "n/a" else {
            log.error("agent.refresh.skipped reason=bundled-hash-unavailable")
            return
        }

        if runningHash == bundledHash {
            lastAutoRefreshAttemptedHash = nil
            return
        }

        guard lastAutoRefreshAttemptedHash != bundledHash else { return }
        lastAutoRefreshAttemptedHash = bundledHash

        log.notice(
            "agent.refresh.needed runningHash=\(runningHash, privacy: .public) bundledHash=\(bundledHash, privacy: .public)"
        )

        let service = SMAppService.agent(plistName: "\(generatedAgentBundleID).plist")
        do {
            try service.unregister()
            try service.register()
            lastError = nil
            log.notice("agent.refresh.done bundledHash=\(bundledHash, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            log.error("agent.refresh.failed error=\(error.localizedDescription, privacy: .public)")
        }
    }
}
