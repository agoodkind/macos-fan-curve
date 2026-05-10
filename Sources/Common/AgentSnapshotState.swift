//
//  AgentSnapshotState.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026
//

import AppKit
import AppLog
import Foundation

private let agentSnapshotStateLog = AppLog.make(category: "AgentSnapshotState")

@MainActor
final class AgentSnapshotState: ObservableObject {
    private enum RefreshMode {
        case interactive
        case passiveVisible
        case occluded

        var intervalNanoseconds: UInt64 {
            switch self {
            case .interactive: return 80_000_000
            case .passiveVisible: return 1_200_000_000
            case .occluded: return 3_000_000_000
            }
        }
    }

    @Published private(set) var snapshot: AgentSnapshot?

    private let defaults: UserDefaults
    private var isAppActive = NSApp.isActive
    private var isAppHidden = NSApp.isHidden
    private var scheduledRefreshTask: Task<Void, Never>?
    private var didStart = false
    private var notificationTokens: [NSObjectProtocol] = []

    init(defaults: UserDefaults = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard) {
        self.defaults = defaults
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        snapshot = AgentSnapshotStore.load(defaults: defaults)
        isAppActive = NSApp.isActive
        isAppHidden = NSApp.isHidden

        notificationTokens = makeLifecycleObserverTokens() + makeWindowObserverTokens()
        registerDarwinSnapshotObserver()
    }

    func stop() {
        guard didStart else { return }
        didStart = false
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = nil
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()
        let token = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            token,
            CFNotificationName(AgentSnapshotPush.notificationName),
            nil)
    }

    var governingTemperature: Double { snapshot?.governingTemperatureC ?? 0 }
    var committedTemperature: Double { snapshot?.committedTemperatureC ?? 0 }
    var rawPressureTemperature: Double? { snapshot?.rawPressureTemperatureC }
    var fans: [AgentFanSnapshot] { snapshot?.fans ?? [] }
    var cpuLoadPercent: Double { snapshot?.cpuLoadPercent ?? 0 }
    var gpuLoadPercent: Double { snapshot?.gpuLoadPercent ?? 0 }
    var effectiveCurvePercent: Double { snapshot?.effectiveCurvePercent ?? 0 }
    var baseCurvePercent: Double { snapshot?.baseCurvePercent ?? 0 }
    var rawBaselinePercent: Double { snapshot?.rawBaselinePercent ?? 0 }
    var semanticDemandPercent: Double? { snapshot?.semanticDemandPercent }
    var thermalDemandSource: ThermalDemandSource { snapshot?.thermalDemandSource ?? .curve }
    var semanticDemandTemperature: Double? { snapshot?.semanticDemandTemperatureC }
    var commandedTargetPercent: Double { snapshot?.commandedTargetPercent ?? snapshot?.committedPercent ?? 0 }
    var commandedTargetTemperature: Double? { snapshot?.commandedTargetTemperatureC }
    var committedPercent: Double { snapshot?.committedPercent ?? 0 }
    var controllerMode: AgentControllerMode { snapshot?.controllerMode ?? .holding }
    var bandIndex: Int { snapshot?.bandIndex ?? 0 }
    var holdRemainingSeconds: Double { snapshot?.holdRemainingSeconds ?? 0 }
    var assistFloorPercent: Double? { snapshot?.assistFloorPercent }
    var activeAssistKinds: [LoadAssistKind] { snapshot?.activeAssistKinds ?? [] }
    var helperReachable: Bool { snapshot?.helperReachable ?? false }
    var boostEnabled: Bool { snapshot?.boostEnabled ?? false }
    var curveActive: Bool { snapshot?.curveActive ?? false }
    var runtimeState: RuntimeState {
        RuntimeState.fromSharedDefaultsSnapshot(snapshot)
    }
    var isFresh: Bool {
        guard let snapshot else { return false }
        return Date().timeIntervalSince(snapshot.timestamp) < 5
    }

    private func handleSnapshotNotification() {
        scheduleReload()
    }

    private func makeLifecycleObserverTokens() -> [NSObjectProtocol] {
        [
            addMainActorObserver(name: NSApplication.didBecomeActiveNotification) { [weak self] in
                guard let self else { return }
                isAppActive = true
                scheduleReload(force: true)
            },
            addMainActorObserver(name: NSApplication.didResignActiveNotification) { [weak self] in
                self?.isAppActive = false
            },
            addMainActorObserver(name: NSApplication.didHideNotification) { [weak self] in
                self?.isAppHidden = true
            },
            addMainActorObserver(name: NSApplication.didUnhideNotification) { [weak self] in
                guard let self else { return }
                isAppHidden = false
                scheduleReload(force: true)
            },
        ]
    }

    private func makeWindowObserverTokens() -> [NSObjectProtocol] {
        let windowNotifications: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
        ]

        return windowNotifications.map { name in
            addMainActorObserver(name: name) { [weak self] in
                self?.handleVisibilityChange()
            }
        }
    }

    private func addMainActorObserver(
        name: Notification.Name,
        handler: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                handler()
            }
        }
    }

    private func registerDarwinSnapshotObserver() {
        let token = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            token,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let state = Unmanaged<AgentSnapshotState>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in state.handleSnapshotNotification() }
            },
            AgentSnapshotPush.notificationName,
            nil,
            .deliverImmediately
        )
    }

    private func handleVisibilityChange() {
        if currentRefreshMode != .occluded {
            scheduleReload(force: true)
        }
    }

    private var currentRefreshMode: RefreshMode {
        if isAppHidden { return .occluded }
        let hasVisibleWindow = NSApp.windows.contains { window in
            window.isVisible
                && !window.isMiniaturized
                && window.occlusionState.contains(.visible)
        }
        if isAppActive, hasVisibleWindow { return .interactive }
        if hasVisibleWindow { return .passiveVisible }
        return .occluded
    }

    private func scheduleReload(force: Bool = false) {
        guard force || scheduledRefreshTask == nil else { return }
        let interval = currentRefreshMode.intervalNanoseconds
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: interval)
            } catch {
                agentSnapshotStateLog.debug("snapshot.reload.cancelled recovery=drop-scheduled-refresh")
                return
            }
            guard !Task.isCancelled else { return }
            self?.scheduledRefreshTask = nil
            self?.reloadSnapshot()
        }
    }

    private func reloadSnapshot() {
        snapshot = AgentSnapshotStore.load(defaults: defaults)
    }
}
