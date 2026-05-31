//
//  WindowRenderActivity.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-24.
//  Copyright © 2026, all rights reserved.
//

import AppKit
import AppLog

private let windowRenderActivityLog = AppLog.make(category: "WindowRenderActivity")

@MainActor
final class WindowRenderActivity: ObservableObject {
    @Published private(set) var mode: AppRenderMode = .occluded

    private let windowTitle: String
    private weak var attachedWindow: NSWindow?
    private var tokens: [NSObjectProtocol] = []
    private var didStart = false

    init(windowTitle: String) {
        self.windowTitle = windowTitle
    }

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

    func attach(window: NSWindow?) {
        guard attachedWindow !== window else {
            refresh()
            return
        }

        attachedWindow = window
        windowRenderActivityLog.info(
            "window_render.window.attached expected_title=\(windowTitle, privacy: .public) actual_title=\(window?.title ?? "none", privacy: .public)"
        )
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
        let nextMode = currentMode()
        if mode != nextMode {
            windowRenderActivityLog.info(
                "window_render.mode.changed window=\(windowTitle, privacy: .public) from=\(String(describing: mode), privacy: .public) to=\(String(describing: nextMode), privacy: .public)"
            )
            mode = nextMode
        }
    }

    private func currentMode(app: NSApplication = .shared) -> AppRenderMode {
        guard let window = attachedWindow ?? targetWindow(in: app) else {
            return .occluded
        }
        guard window.isVisible, !window.isMiniaturized else {
            return .occluded
        }

        let isVisible =
            window.occlusionState.contains(.visible)
            || window.isKeyWindow
            || window.isMainWindow
        guard isVisible else {
            return .occluded
        }

        if app.isActive, window.isKeyWindow || window.isMainWindow {
            return .interactive
        }

        return .backgroundVisible
    }

    private func targetWindow(in app: NSApplication) -> NSWindow? {
        app.windows.first { $0.title == windowTitle }
    }
}
