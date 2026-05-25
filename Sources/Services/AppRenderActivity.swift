//
//  AppRenderActivity.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-27.
//  Copyright © 2026
//

import AppKit
import AppLog
import SwiftUI

private let appRenderActivityLog = AppLog.make(category: "AppRenderActivity")

enum AppRenderMode: Equatable, Hashable {
    case backgroundVisible
    case interactive
    case occluded

    var isVisible: Bool {
        self != .occluded
    }

    var allowsLiveAnimation: Bool {
        self != .occluded
    }

    var showsLiveDashboard: Bool {
        self == .interactive
    }

    var preferredFramesPerSecond: Int {
        switch self {
        case .interactive, .backgroundVisible: return Self.maximumDisplayFramesPerSecond
        case .occluded: return 1
        }
    }

    private static var maximumDisplayFramesPerSecond: Int {
        max(60, NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 60)
    }

    var frameProfilerSchedule: PeriodicTimelineSchedule {
        PeriodicTimelineSchedule(
            from: .now,
            by: 1.0 / Double(preferredFramesPerSecond)
        )
    }
}

@MainActor
final class AppRenderActivity: ObservableObject {
    @Published private(set) var mode: AppRenderMode = .interactive

    private var tokens: [NSObjectProtocol] = []
    private var didStart = false

    func start() {
        guard !didStart else { return }
        didStart = true

        let notifications: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
            NSApplication.didHideNotification,
            NSApplication.didUnhideNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignMainNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]

        tokens = notifications.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            }
        }

        refresh()
    }

    func stop() {
        guard didStart else { return }
        didStart = false
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
        tokens.removeAll()
    }

    func refresh() {
        let nextMode = Self.currentMode()
        if mode != nextMode {
            appRenderActivityLog.info(
                "render.mode.changed from=\(String(describing: mode), privacy: .public) to=\(String(describing: nextMode), privacy: .public) fps=\(nextMode.preferredFramesPerSecond, privacy: .public)"
            )
            mode = nextMode
        }
    }

    private static func currentMode() -> AppRenderMode {
        switch currentAppVisibilityState() {
        case .interactive:
            return .interactive
        case .passiveVisible:
            return .backgroundVisible
        case .occluded:
            return .occluded
        }
    }
}
