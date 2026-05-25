//
//  InstallationState+AgentLifecycle.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-24.
//  Copyright © 2026
//

import AppLog
import Foundation
import ServiceManagement

private let installationStateAgentLifecycleLog = AppLog.make(category: "InstallationState")

struct ServiceRegistrationFingerprints {
    let agent: String
    let helper: String
}

struct AgentRefreshContext {
    let agentConnected: Bool
    let runningHash: String
    let snapshotSchemaVersion: Int?
    let storedFingerprint: String?
    let expectedFingerprint: String
    let defaults: UserDefaults

    var registrationMismatch: Bool {
        storedFingerprint != expectedFingerprint
    }

    var snapshotSchemaMismatch: Bool {
        snapshotSchemaVersion.map { $0 != AgentSnapshot.currentSchemaVersion } ?? false
    }
}

struct LegacyLaunchAgentRepairResult {
    let repaired: Bool
    let sourcePath: String
    let backupPath: String?
    let reason: String
}

struct LegacyLaunchAgentPlist: Decodable {
    let label: String?
    let program: String?
    let programArguments: [String]

    enum CodingKeys: String, CodingKey {
        case label = "Label"
        case program = "Program"
        case programArguments = "ProgramArguments"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        program = try container.decodeIfPresent(String.self, forKey: .program)
        programArguments =
            try container.decodeIfPresent([String].self, forKey: .programArguments) ?? []
    }
}

extension InstallationState {
    func autoRegisterAgentIfNeeded(
        agentStatus: SMAppService.Status,
        appBundlePath: String,
        applyInBackground: Bool,
        storedFingerprint: String?
    ) async -> SMAppService.Status {
        guard #available(macOS 13.0, *) else { return agentStatus }
        guard agentStatus != .enabled, agentStatus != .requiresApproval else {
            return agentStatus
        }
        guard isLocalStagedBundle(path: appBundlePath) else {
            return agentStatus
        }
        guard applyInBackground, storedFingerprint != nil else {
            return agentStatus
        }

        let now = Date()
        let retriedTooRecently =
            lastAutoRegisterAttemptDate.map { lastAttemptDate in
                now.timeIntervalSince(lastAttemptDate) < agentAutoRegisterRetryInterval
            } ?? false
        if retriedTooRecently {
            return agentStatus
        }
        lastAutoRegisterAttemptDate = now

        installationStateAgentLifecycleLog.notice(
            "agent.auto_register.started appPath=\(appBundlePath, privacy: .public) status=\(agentStatus.rawValue, privacy: .public)"
        )
        let result = await Self.registerAgentService()
        if let errorDescription = result.errorDescription {
            lastError = errorDescription
            installationStateAgentLifecycleLog.error(
                "agent.auto_register.failed appPath=\(appBundlePath, privacy: .public) error=\(errorDescription, privacy: .public) recovery=show-agent-install-state"
            )
            return agentStatus
        }

        let refreshedStatus = await currentAgentStatus()
        lastAgentServiceRegisterDate = Date()
        installationStateAgentLifecycleLog.notice(
            "agent.auto_register.done appPath=\(appBundlePath, privacy: .public) status=\(refreshedStatus.rawValue, privacy: .public)"
        )
        return refreshedStatus
    }

    func currentAgentStatus() async -> SMAppService.Status {
        guard #available(macOS 13.0, *) else { return .notFound }
        let rawValue = await Self.currentAgentStatusRawValue()
        return SMAppService.Status(rawValue: rawValue) ?? .notFound
    }

    func refreshAgentIfNeeded(_ context: AgentRefreshContext) async {
        guard #available(macOS 13.0, *) else { return }

        let appBundlePath = Bundle.main.bundleURL.path
        let stagedBundle = isLocalStagedBundle(path: appBundlePath)
        let bundledHash = BuildFingerprint.bundledAgentHash
        guard bundledAgentHashIsAvailable(bundledHash) else { return }
        logRefreshContextIfNeeded(appBundlePath: appBundlePath, stagedBundle: stagedBundle)
        guard
            runningAgentHashIsAvailable(
                context: context,
                appBundlePath: appBundlePath,
                bundledHash: bundledHash
            )
        else { return }
        if reconcileCurrentAgentIfNeeded(
            context: context,
            appBundlePath: appBundlePath,
            bundledHash: bundledHash
        ) {
            return
        }
        guard
            shouldRefreshDisconnectedAgent(
                context: context,
                appBundlePath: appBundlePath,
                bundledHash: bundledHash
            )
        else { return }

        let result = await Self.refreshRegisteredAgent()
        finishAgentRefresh(
            result: result,
            context: context,
            appBundlePath: appBundlePath,
            stagedBundle: stagedBundle,
            bundledHash: bundledHash
        )
    }

    func bundledAgentHashIsAvailable(_ bundledHash: String) -> Bool {
        guard bundledHash != "n/a" else {
            installationStateAgentLifecycleLog.error(
                "agent.refresh.skipped reason=bundled-hash-unavailable"
            )
            return false
        }
        return true
    }

    func logRefreshContextIfNeeded(appBundlePath: String, stagedBundle: Bool) {
        guard !stagedBundle else { return }
        installationStateAgentLifecycleLog.notice(
            "agent.refresh.context appPath=\(appBundlePath, privacy: .public) mode=non-staged-bundle"
        )
    }

    func runningAgentHashIsAvailable(
        context: AgentRefreshContext,
        appBundlePath: String,
        bundledHash: String
    ) -> Bool {
        guard !context.runningHash.isEmpty else {
            return missingRunningHashCanTriggerRefresh(
                context: context,
                appBundlePath: appBundlePath,
                bundledHash: bundledHash
            )
        }
        return true
    }

    func missingRunningHashCanTriggerRefresh(
        context: AgentRefreshContext,
        appBundlePath: String,
        bundledHash: String
    ) -> Bool {
        if agentStartupGracePeriodIsActive() {
            installationStateAgentLifecycleLog.notice(
                "agent.refresh.deferred appPath=\(appBundlePath, privacy: .public) reason=running-hash-unavailable bundledHash=\(bundledHash, privacy: .public) schemaMismatch=\(context.snapshotSchemaMismatch, privacy: .public) recovery=wait-for-agent-snapshot"
            )
            return false
        }
        installationStateAgentLifecycleLog.notice(
            "agent.refresh.continuing appPath=\(appBundlePath, privacy: .public) reason=running-hash-unavailable bundledHash=\(bundledHash, privacy: .public) schemaMismatch=\(context.snapshotSchemaMismatch, privacy: .public) recovery=refresh-stale-agent-registration"
        )
        return true
    }

    func agentStartupGracePeriodIsActive() -> Bool {
        guard let lastAgentServiceRegisterDate else { return false }
        return Date().timeIntervalSince(lastAgentServiceRegisterDate) < agentStartupGraceInterval
    }

    func reconcileCurrentAgentIfNeeded(
        context: AgentRefreshContext,
        appBundlePath: String,
        bundledHash: String
    ) -> Bool {
        guard context.runningHash == bundledHash, !context.snapshotSchemaMismatch else {
            return false
        }
        if context.registrationMismatch {
            context.defaults.set(
                context.expectedFingerprint, forKey: SharedConfigKeys.agentRegistrationFingerprint)
            installationStateAgentLifecycleLog.notice(
                "agent.refresh.fingerprint_reconciled appPath=\(appBundlePath, privacy: .public) bundledHash=\(bundledHash, privacy: .public) recovery=keep-running-agent"
            )
        }
        clearRefreshAttempt()
        return true
    }

    func shouldRefreshDisconnectedAgent(
        context: AgentRefreshContext,
        appBundlePath: String,
        bundledHash: String
    ) -> Bool {
        guard !context.agentConnected else {
            installationStateAgentLifecycleLog.notice(
                "agent.refresh.deferred appPath=\(appBundlePath, privacy: .public) reason=agent-xpc-connected runningHash=\(context.runningHash, privacy: .public) bundledHash=\(bundledHash, privacy: .public) schemaMismatch=\(context.snapshotSchemaMismatch, privacy: .public) recovery=avoid-live-agent-restart"
            )
            return false
        }
        let now = Date()
        guard shouldRetryRefresh(for: bundledHash, now: now) else {
            installationStateAgentLifecycleLog.notice(
                "agent.refresh.deferred appPath=\(appBundlePath, privacy: .public) bundledHash=\(bundledHash, privacy: .public) recovery=wait-before-retrying"
            )
            return false
        }
        recordRefreshAttempt(for: bundledHash, at: now)
        return true
    }

    func finishAgentRefresh(
        result: AgentServiceMutationResult,
        context: AgentRefreshContext,
        appBundlePath: String,
        stagedBundle: Bool,
        bundledHash: String
    ) {
        installationStateAgentLifecycleLog.notice(
            "agent.refresh.needed appPath=\(appBundlePath, privacy: .public) stagedBundle=\(stagedBundle, privacy: .public) status=\(result.statusBefore, privacy: .public) runningHash=\(context.runningHash, privacy: .public) bundledHash=\(bundledHash, privacy: .public) snapshotSchema=\(context.snapshotSchemaVersion ?? -1, privacy: .public) expectedSchema=\(AgentSnapshot.currentSchemaVersion, privacy: .public) schemaMismatch=\(context.snapshotSchemaMismatch, privacy: .public)"
        )

        if let statusAfterUnregister = result.statusAfterUnregister {
            installationStateAgentLifecycleLog.notice(
                "agent.refresh.unregister.done status=\(statusAfterUnregister, privacy: .public)"
            )
        }

        if let errorDescription = result.errorDescription {
            lastError = errorDescription
            installationStateAgentLifecycleLog.error(
                "agent.refresh.failed appPath=\(appBundlePath, privacy: .public) status=\(result.statusBefore, privacy: .public) error=\(errorDescription, privacy: .public) recovery=retry-auto-refresh"
            )
            return
        }

        if let statusAfterRegister = result.statusAfterRegister {
            lastError = nil
            lastAgentServiceRegisterDate = Date()
            clearRefreshAttempt()
            installationStateAgentLifecycleLog.notice(
                "agent.refresh.done appPath=\(appBundlePath, privacy: .public) bundledHash=\(bundledHash, privacy: .public) registrationMismatch=\(context.registrationMismatch, privacy: .public) status=\(statusAfterRegister, privacy: .public)"
            )
            context.defaults.set(
                context.expectedFingerprint, forKey: SharedConfigKeys.agentRegistrationFingerprint)
        }
    }

    func serviceRegistrationFingerprints() -> ServiceRegistrationFingerprints {
        ServiceRegistrationFingerprints(
            agent: [
                generatedAppBundleID,
                generatedAppDisplayName,
                generatedAgentBundleID,
                generatedAgentDisplayName,
                generatedAgentExecutableName,
                BuildFingerprint.bundledAgentHash,
            ].joined(separator: "|"),
            helper: [
                generatedAppBundleID,
                generatedAppDisplayName,
                generatedHelperBundleID,
                generatedHelperDisplayName,
                BuildFingerprint.bundledHelperHash,
            ].joined(separator: "|")
        )
    }

    func isLocalStagedBundle(path: String) -> Bool {
        path.hasSuffix("/Products/FanCurve.app") || path.hasSuffix("/Products/Fan Curve.app")
    }

    func shouldRetryRefresh(for bundledHash: String, now: Date) -> Bool {
        guard lastAutoRefreshAttemptedHash == bundledHash else { return true }
        guard let lastAutoRefreshAttemptDate else { return true }
        return now.timeIntervalSince(lastAutoRefreshAttemptDate) >= agentRefreshRetryInterval
    }

    func recordRefreshAttempt(for bundledHash: String, at date: Date) {
        lastAutoRefreshAttemptedHash = bundledHash
        lastAutoRefreshAttemptDate = date
    }

    func clearRefreshAttempt() {
        lastAutoRefreshAttemptedHash = nil
        lastAutoRefreshAttemptDate = nil
    }

    nonisolated static func repairLegacyLaunchAgentIfNeeded() -> LegacyLaunchAgentRepairResult {
        let fileManager = FileManager.default
        let legacyURL = legacyLaunchAgentURL(fileManager: fileManager)
        let legacyPath = legacyURL.path

        guard fileManager.fileExists(atPath: legacyPath) else {
            return LegacyLaunchAgentRepairResult(
                repaired: false,
                sourcePath: legacyPath,
                backupPath: nil,
                reason: "not-found"
            )
        }

        installationStateAgentLifecycleLog.notice(
            "agent.legacy_plist.inspect.started path=\(legacyPath, privacy: .public)"
        )

        let legacyPlistResult = readLegacyLaunchAgent(at: legacyURL)
        guard let legacyPlist = legacyPlistResult.plist else {
            return legacyPlistResult.repairResult
        }

        guard legacyPlist.label == generatedAgentBundleID else {
            installationStateAgentLifecycleLog.notice(
                "agent.legacy_plist.keep path=\(legacyPath, privacy: .public) reason=label-mismatch"
            )
            return LegacyLaunchAgentRepairResult(
                repaired: false,
                sourcePath: legacyPath,
                backupPath: nil,
                reason: "label-mismatch"
            )
        }

        guard
            let repairReason = legacyLaunchAgentRepairReason(
                plist: legacyPlist,
                fileManager: fileManager
            )
        else {
            installationStateAgentLifecycleLog.notice(
                "agent.legacy_plist.keep path=\(legacyPath, privacy: .public) reason=current-bundle"
            )
            return LegacyLaunchAgentRepairResult(
                repaired: false,
                sourcePath: legacyPath,
                backupPath: nil,
                reason: "current-bundle"
            )
        }

        return moveLegacyLaunchAgent(at: legacyURL, reason: repairReason)
    }

    nonisolated static func legacyLaunchAgentURL(fileManager: FileManager) -> URL {
        fileManager
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(generatedAgentBundleID).plist", isDirectory: false)
    }

    nonisolated static func readLegacyLaunchAgent(
        at legacyURL: URL
    ) -> (plist: LegacyLaunchAgentPlist?, repairResult: LegacyLaunchAgentRepairResult) {
        do {
            let legacyData = try Data(contentsOf: legacyURL)
            let plist = try PropertyListDecoder().decode(
                LegacyLaunchAgentPlist.self,
                from: legacyData
            )
            let repairResult = LegacyLaunchAgentRepairResult(
                repaired: false,
                sourcePath: legacyURL.path,
                backupPath: nil,
                reason: "read"
            )
            return (plist, repairResult)
        } catch {
            installationStateAgentLifecycleLog.error(
                "agent.legacy_plist.read.failed path=\(legacyURL.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=keep-file"
            )
            let repairResult = LegacyLaunchAgentRepairResult(
                repaired: false,
                sourcePath: legacyURL.path,
                backupPath: nil,
                reason: "read-failed"
            )
            return (nil, repairResult)
        }
    }

    nonisolated static func legacyLaunchAgentRepairReason(
        plist legacyPlist: LegacyLaunchAgentPlist,
        fileManager: FileManager
    ) -> String? {
        let programPath = legacyProgramPath(from: legacyPlist)
        let currentBundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        let usesLegacyProgramArguments = !legacyPlist.programArguments.isEmpty
        let pointsOutsideCurrentBundle =
            programPath.map { !$0.hasPrefix("\(currentBundlePath)/") } ?? true
        let pointsToMissingExecutable =
            programPath.map { !fileManager.isExecutableFile(atPath: $0) } ?? true

        guard usesLegacyProgramArguments || pointsOutsideCurrentBundle || pointsToMissingExecutable
        else {
            return nil
        }

        if pointsToMissingExecutable {
            return "missing-executable"
        }
        if pointsOutsideCurrentBundle {
            return "outside-current-bundle"
        }
        return "legacy-program-arguments"
    }

    nonisolated static func legacyProgramPath(from plist: LegacyLaunchAgentPlist) -> String? {
        if let program = plist.program {
            return program
        }

        return plist.programArguments.first
    }

    nonisolated static func moveLegacyLaunchAgent(
        at legacyURL: URL,
        reason: String
    ) -> LegacyLaunchAgentRepairResult {
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupFileName =
            "\(legacyURL.lastPathComponent).fancurve-migrated-\(timestamp)"

        let backupURL =
            legacyURL
            .deletingLastPathComponent()
            .appendingPathComponent(backupFileName, isDirectory: false)

        do {
            try FileManager.default.moveItem(at: legacyURL, to: backupURL)
            installationStateAgentLifecycleLog.notice(
                "agent.legacy_plist.moved path=\(legacyURL.path, privacy: .public) backup=\(backupURL.path, privacy: .public) reason=\(reason, privacy: .public)"
            )
            return LegacyLaunchAgentRepairResult(
                repaired: true,
                sourcePath: legacyURL.path,
                backupPath: backupURL.path,
                reason: reason
            )
        } catch {
            installationStateAgentLifecycleLog.error(
                "agent.legacy_plist.move.failed path=\(legacyURL.path, privacy: .public) backup=\(backupURL.path, privacy: .public) reason=\(reason, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=keep-file"
            )
            return LegacyLaunchAgentRepairResult(
                repaired: false,
                sourcePath: legacyURL.path,
                backupPath: nil,
                reason: "move-failed"
            )
        }
    }
}
