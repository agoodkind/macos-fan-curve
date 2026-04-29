//
//  AppRenderActivity.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-27.
//  Copyright © 2026
//

import AppKit
import SwiftUI

enum AppRenderMode: Equatable {
    case interactive
    case backgroundVisible
    case occluded

    var isVisible: Bool {
        self != .occluded
    }

    var preferredFramesPerSecond: Int {
        switch self {
        case .interactive: return 60
        case .backgroundVisible: return 15
        case .occluded: return 1
        }
    }

    var frameProfilerSchedule: PeriodicTimelineSchedule {
        PeriodicTimelineSchedule(
            from: .now,
            by: 1.0 / Double(preferredFramesPerSecond)
        )
    }

    var markerSmoothingIntervalNanoseconds: UInt64 {
        switch self {
        case .interactive: return 16_000_000
        case .backgroundVisible: return 120_000_000
        case .occluded: return 1_000_000_000
        }
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
