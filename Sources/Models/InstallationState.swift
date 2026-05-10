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
private struct AgentServiceMutationResult: Sendable {
    let statusBefore: String
    let statusAfterUnregister: String?
    let statusAfterRegister: String?
    let errorDescription: String?
}

private struct ServiceRegistrationFingerprints {
    let agent: String
}

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
    @Published var helperRawStatus: Int = 0
    @Published var agentRawStatus: Int = 0
    /// Timestamp of the Agent's last successful tick, read from the shared
    /// UserDefaults suite on each refresh. 0 when unset.
    @Published var agentLastTickEpoch: Double = 0
    /// Last error string reported by the Agent, empty when the last tick
    /// succeeded or the Agent has never written one.
    @Published var agentLastError: String = ""
    @Published var agentExecutableHash: String = ""
    @Published var agentSnapshotSchemaVersion: Int?
    @Published private(set) var isRegisteringAgent = false
    @Published private(set) var isRegisteringHelper = false

    private var timer: Timer?
    private var lastAutoRefreshAttemptedHash: String?
    private var lastAutoRefreshAttemptDate: Date?
    private let agentRefreshRetryInterval: TimeInterval = 30

    /// Convenience computed helpers for the Settings UI.
    var agentEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.Status(rawValue: agentRawStatus) == .enabled
    }

    var helperEnabled: Bool {
        step == .ready
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

    var agentSnapshotCompatible: Bool {
        guard let agentSnapshotSchemaVersion else { return true }
        return agentSnapshotSchemaVersion == AgentSnapshot.currentSchemaVersion
    }

    func startMonitoring(agentClient: FanCurveAgentClient) {
        Task { await refresh(agentClient: agentClient) }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if let self {
                    await self.refresh(agentClient: agentClient)
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
        guard !isRegisteringAgent else {
            log.notice("agent.register.skipped reason=registration-in-progress recovery=keep-current-registration")
            return
        }
        isRegisteringAgent = true
        log.notice("agent.register.started")
        Task {
            defer {
                isRegisteringAgent = false
                log.notice("agent.register.finished")
            }
            let result = await Self.registerAgentService()
            log.notice(
                "agent.register.requested plist=\(generatedAgentPlistName, privacy: .public) status=\(result.statusBefore, privacy: .public)"
            )

            if let errorDescription = result.errorDescription {
                lastError = errorDescription
                log.error(
                    "agent.register.failed error=\(errorDescription, privacy: .public) recovery=show-login-item-error"
                )
                return
            }

            lastError = nil
            log.notice("agent.register.done status=\(result.statusAfterRegister ?? "unknown", privacy: .public)")
        }
    }

    func registerHelperDaemon(agentClient: FanCurveAgentClient) {
        guard !isRegisteringHelper else {
            log.notice("helper.register.skipped reason=registration-in-progress recovery=keep-current-registration")
            return
        }
        isRegisteringHelper = true
        log.notice("helper.register.started owner=agent-xpc")
        Task {
            defer {
                isRegisteringHelper = false
                log.notice("helper.register.finished")
            }
            do {
                try await agentClient.registerHelperDaemon()
                lastError = nil
                log.notice("helper.register.done owner=agent-xpc")
                await refresh(agentClient: agentClient)
            } catch {
                lastError = error.localizedDescription
                log.error(
                    "helper.register.failed owner=agent-xpc error=\(error.localizedDescription, privacy: .public) recovery=show-login-item-error"
                )
            }
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
        Task {
            let result = await Self.unregisterAgentService()
            log.notice(
                "agent.unregister.requested plist=\(generatedAgentPlistName, privacy: .public) status=\(result.statusBefore, privacy: .public)"
            )

            if let errorDescription = result.errorDescription {
                lastError = errorDescription
                log.error(
                    "agent.unregister.failed error=\(errorDescription, privacy: .public) recovery=show-login-item-error"
                )
                return
            }

            lastError = nil
            log.notice("agent.unregister.done status=\(result.statusAfterUnregister ?? "unknown", privacy: .public)")
        }
    }

    /// Probes current installation status.
    private func refresh(agentClient: FanCurveAgentClient) async {
        let agentStatus = await currentAgentStatus()
        let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
        let helperOK = agentClient.helperReachable
        let runtimeSetup = agentClient.runtimeState.setup

        helperReachable = helperOK
        helperRawStatus = Self.helperRawStatus(from: runtimeSetup, helperReachable: helperOK)
        agentRawStatus = agentStatus.rawValue

        agentLastTickEpoch = suite.double(forKey: SharedConfigKeys.agentLastTick)
        agentExecutableHash = suite.string(forKey: SharedConfigKeys.agentExecutableHash) ?? ""
        agentLastError = suite.string(forKey: SharedConfigKeys.agentLastError) ?? ""
        agentSnapshotSchemaVersion = AgentSnapshotStore.storedSchemaVersion(defaults: suite)

        let fingerprints = serviceRegistrationFingerprints()
        if agentStatus == .enabled {
            await refreshAgentIfNeeded(
                runningHash: agentExecutableHash,
                snapshotSchemaVersion: agentSnapshotSchemaVersion,
                storedFingerprint: suite.string(forKey: SharedConfigKeys.agentRegistrationFingerprint),
                expectedFingerprint: fingerprints.agent,
                defaults: suite)
        }

        if agentStatus == .requiresApproval {
            step = .agentAwaitingApproval
            return
        }

        if agentStatus != .enabled {
            step = .agentMissing
            return
        }

        guard agentClient.connectionState == .connected else {
            log.debug(
                "agent.xpc.unavailable connection=\(String(describing: agentClient.connectionState), privacy: .public) recovery=wait-for-agent-runtime-state"
            )
            step = .checking
            return
        }

        step = Self.installationStep(from: runtimeSetup)
    }

    private func currentAgentStatus() async -> SMAppService.Status {
        guard #available(macOS 13.0, *) else { return .notFound }
        let rawValue = await Self.currentAgentStatusRawValue()
        return SMAppService.Status(rawValue: rawValue) ?? .notFound
    }

    private func refreshAgentIfNeeded(
        runningHash: String,
        snapshotSchemaVersion: Int?,
        storedFingerprint: String?,
        expectedFingerprint: String,
        defaults: UserDefaults
    ) async {
        guard #available(macOS 13.0, *) else { return }

        let appBundlePath = Bundle.main.bundleURL.path
        let stagedBundle = isLocalStagedBundle(path: appBundlePath)
        let bundledHash = BuildFingerprint.bundledAgentHash
        let registrationMismatch = storedFingerprint != expectedFingerprint
        let snapshotSchemaMismatch = snapshotSchemaVersion.map { $0 != AgentSnapshot.currentSchemaVersion } ?? false
        guard bundledHash != "n/a" else {
            log.error("agent.refresh.skipped reason=bundled-hash-unavailable")
            return
        }

        if !stagedBundle {
            log.notice("agent.refresh.context appPath=\(appBundlePath, privacy: .public) mode=non-staged-bundle")
        }

        if runningHash == bundledHash, !snapshotSchemaMismatch, !registrationMismatch {
            clearRefreshAttempt()
            return
        }

        let now = Date()
        guard shouldRetryRefresh(for: bundledHash, now: now) else {
            log.notice(
                "agent.refresh.deferred appPath=\(appBundlePath, privacy: .public) bundledHash=\(bundledHash, privacy: .public) recovery=wait-before-retrying"
            )
            return
        }

        recordRefreshAttempt(for: bundledHash, at: now)
        let result = await Self.refreshRegisteredAgentService()
        log.notice(
            "agent.refresh.needed appPath=\(appBundlePath, privacy: .public) stagedBundle=\(stagedBundle, privacy: .public) status=\(result.statusBefore, privacy: .public) runningHash=\(runningHash, privacy: .public) bundledHash=\(bundledHash, privacy: .public) snapshotSchema=\(snapshotSchemaVersion ?? -1, privacy: .public) expectedSchema=\(AgentSnapshot.currentSchemaVersion, privacy: .public) schemaMismatch=\(snapshotSchemaMismatch, privacy: .public)"
        )

        if let statusAfterUnregister = result.statusAfterUnregister {
            log.notice("agent.refresh.unregister.done status=\(statusAfterUnregister, privacy: .public)")
        }

        if let errorDescription = result.errorDescription {
            lastError = errorDescription
            log.error(
                "agent.refresh.failed appPath=\(appBundlePath, privacy: .public) status=\(result.statusBefore, privacy: .public) error=\(errorDescription, privacy: .public) recovery=retry-auto-refresh"
            )
            return
        }

        if let statusAfterRegister = result.statusAfterRegister {
            lastError = nil
            clearRefreshAttempt()
            log.notice(
                "agent.refresh.done appPath=\(appBundlePath, privacy: .public) bundledHash=\(bundledHash, privacy: .public) registrationMismatch=\(registrationMismatch, privacy: .public) status=\(statusAfterRegister, privacy: .public)"
            )
            defaults.set(expectedFingerprint, forKey: SharedConfigKeys.agentRegistrationFingerprint)
        }
    }

    private func serviceRegistrationFingerprints() -> ServiceRegistrationFingerprints {
        ServiceRegistrationFingerprints(
            agent: [
                generatedAppBundleID,
                generatedAppDisplayName,
                generatedAgentBundleID,
                generatedAgentDisplayName,
                generatedAgentExecutableName,
                BuildFingerprint.bundledAgentHash,
            ].joined(separator: "|")
        )
    }

    @available(macOS 13.0, *)
    nonisolated private static func agentService() -> SMAppService {
        SMAppService.agent(plistName: generatedAgentPlistName)
    }

    @available(macOS 13.0, *)
    nonisolated private static func describeAgentStatus(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            "enabled"
        case .requiresApproval:
            "requiresApproval"
        case .notFound:
            "notFound"
        case .notRegistered:
            "notRegistered"
        default:
            "unknown(\(status.rawValue))"
        }
    }

    @available(macOS 13.0, *)
    nonisolated private static func currentAgentStatusRawValue() async -> Int {
        await Task.detached {
            agentService().status.rawValue
        }.value
    }

    @available(macOS 13.0, *)
    nonisolated private static func registerAgentService() async -> AgentServiceMutationResult {
        await Task.detached {
            let service = agentService()
            let statusBefore = describeAgentStatus(service.status)
            do {
                try service.register()
                return AgentServiceMutationResult(
                    statusBefore: statusBefore,
                    statusAfterUnregister: nil,
                    statusAfterRegister: describeAgentStatus(service.status),
                    errorDescription: nil
                )
            } catch {
                log.error(
                    "agent.register.service.failed status=\(statusBefore, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-ui"
                )
                return AgentServiceMutationResult(
                    statusBefore: statusBefore,
                    statusAfterUnregister: nil,
                    statusAfterRegister: nil,
                    errorDescription: error.localizedDescription
                )
            }
        }.value
    }

    @available(macOS 13.0, *)
    nonisolated private static func unregisterAgentService() async -> AgentServiceMutationResult {
        await Task.detached {
            let service = agentService()
            let statusBefore = describeAgentStatus(service.status)
            do {
                try service.unregister()
                return AgentServiceMutationResult(
                    statusBefore: statusBefore,
                    statusAfterUnregister: describeAgentStatus(service.status),
                    statusAfterRegister: nil,
                    errorDescription: nil
                )
            } catch {
                log.error(
                    "agent.unregister.service.failed status=\(statusBefore, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-ui"
                )
                return AgentServiceMutationResult(
                    statusBefore: statusBefore,
                    statusAfterUnregister: nil,
                    statusAfterRegister: nil,
                    errorDescription: error.localizedDescription
                )
            }
        }.value
    }

    @available(macOS 13.0, *)
    nonisolated private static func refreshRegisteredAgentService() async -> AgentServiceMutationResult {
        await Task.detached {
            let service = agentService()
            let statusBefore = describeAgentStatus(service.status)
            do {
                try service.unregister()
                let statusAfterUnregister = describeAgentStatus(service.status)
                try service.register()
                return AgentServiceMutationResult(
                    statusBefore: statusBefore,
                    statusAfterUnregister: statusAfterUnregister,
                    statusAfterRegister: describeAgentStatus(service.status),
                    errorDescription: nil
                )
            } catch {
                log.error(
                    "agent.refresh.service.failed status=\(statusBefore, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=return-error-to-refresh-loop"
                )
                return AgentServiceMutationResult(
                    statusBefore: statusBefore,
                    statusAfterUnregister: nil,
                    statusAfterRegister: nil,
                    errorDescription: error.localizedDescription
                )
            }
        }.value
    }

    private func isLocalStagedBundle(path: String) -> Bool {
        path.hasSuffix("/Products/FanCurve.app") || path.hasSuffix("/Products/Fan Curve.app")
    }

    private func shouldRetryRefresh(for bundledHash: String, now: Date) -> Bool {
        guard lastAutoRefreshAttemptedHash == bundledHash else { return true }
        guard let lastAutoRefreshAttemptDate else { return true }
        return now.timeIntervalSince(lastAutoRefreshAttemptDate) >= agentRefreshRetryInterval
    }

    private func recordRefreshAttempt(for bundledHash: String, at date: Date) {
        lastAutoRefreshAttemptedHash = bundledHash
        lastAutoRefreshAttemptDate = date
    }

    private func clearRefreshAttempt() {
        lastAutoRefreshAttemptedHash = nil
        lastAutoRefreshAttemptDate = nil
    }

    nonisolated private static func installationStep(from setup: SetupState) -> Step {
        switch setup {
        case .backgroundAgentApproval:
            return .agentAwaitingApproval
        case .backgroundAgentRequired:
            return .agentMissing
        case .helperApproval:
            return .helperAwaitingApproval
        case .helperRequired:
            return .helperMissing
        case .ready:
            return .ready
        }
    }

    nonisolated private static func helperRawStatus(from setup: SetupState, helperReachable: Bool) -> Int {
        guard #available(macOS 13.0, *) else { return 0 }
        switch setup {
        case .helperApproval:
            return SMAppService.Status.requiresApproval.rawValue
        case .helperRequired:
            return helperReachable
                ? SMAppService.Status.enabled.rawValue
                : SMAppService.Status.notRegistered.rawValue
        case .ready:
            return SMAppService.Status.enabled.rawValue
        case .backgroundAgentApproval, .backgroundAgentRequired:
            return SMAppService.Status.notFound.rawValue
        }
    }
}
