//
//  FanOwnershipStatus.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-21.
//  Copyright © 2026, all rights reserved.
//
//  Observable wrapper around FanCurveAgent XPC ownership reads for the
//  Settings surface. The poller only runs while its owning view is visible.
//

import AppLog
import Combine
import Foundation

private let log = AppLog.make(category: "FanOwnershipStatus")

@MainActor
final class FanOwnershipStatus: ObservableObject {
    @Published var reachable: Bool = false
    @Published var rows: [AgentOwnershipEntry] = []
    @Published var lastError: String?
    @Published var hasLoaded: Bool = false
    @Published var isMonitoring: Bool = false

    private var timer: Timer?

    // Owners must call `stopMonitoring` before dropping the last reference.
    // SwiftUI's `.onAppear` / `.onDisappear` pair already provides this for
    // the Settings screens. We cannot safely invalidate from a `deinit` here
    // because `Timer` is not `Sendable` and a `@MainActor` nonisolated
    // deinit is the default in Swift 6. A leaked timer ticks against a nil
    // `self?` via `[weak self]`, which is a no op rather than a crash.

    func startMonitoring(agentClient: FanCurveAgentClient, intervalSeconds: TimeInterval = 1.0) {
        self.stopMonitoring()
        self.isMonitoring = true
        log.debug(
            "ownership_status.start interval=\(intervalSeconds, privacy: .public)"
        )
        self.timer = Timer.scheduledTimer(
            withTimeInterval: intervalSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.tick(agentClient: agentClient) }
        }
        Task { @MainActor [weak self] in await self?.tick(agentClient: agentClient) }
    }

    func stopMonitoring() {
        self.timer?.invalidate()
        self.timer = nil
        self.isMonitoring = false
        log.debug("ownership_status.stop")
    }

    func refreshOnce(agentClient: FanCurveAgentClient) async {
        await tick(agentClient: agentClient)
    }

    private func tick(agentClient: FanCurveAgentClient) async {
        do {
            let entries = try await agentClient.getOwnership()
            self.rows = entries
            self.reachable = true
            self.lastError = nil
            self.hasLoaded = true
        } catch {
            self.reachable = false
            self.lastError = error.localizedDescription
            self.hasLoaded = true
            log.notice(
                "ownership_status.unreachable error=\(error.localizedDescription, privacy: .public) recovery=show-helper-unreachable"
            )
        }
    }
}
