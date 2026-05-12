//
//  FanCurveApp.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import AppLog
import SwiftUI

private let log = AppLog.make(category: "AgentMain")

@main
struct FanCurveApp: App {
    @StateObject private var agentClient = FanCurveAgentClient()
    @StateObject private var curveModel = FanCurveModel()
    @StateObject private var appUpdater = AppUpdater()

    init() {
        AppLog.bootstrap(subsystem: "io.goodkind.fan")
        #if DEBUG
            FrameProfiler.shared.startIfEnabled()
        #endif

        // First-run default for the background control preference. Keeping
        // this true preserves existing behavior where the agent continues
        // after the app closes.
        let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
        if suite.object(forKey: SharedConfigKeys.applyInBackground) == nil {
            suite.set(true, forKey: SharedConfigKeys.applyInBackground)
        }
    }

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(agentClient)
                .environmentObject(curveModel)
                .environmentObject(appUpdater)
                .onReceive(
                    NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
                ) { _ in
                    handleTermination()
                }
        }
        .defaultSize(width: 980, height: 540)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",")
            }

            // Replace the default "About Fan Curve" menu command with one
            // that opens our custom About window so the same view is used
            // in both the menu and Settings > About.
            CommandGroup(replacing: .appInfo) {
                Button("About Fan Curve") {
                    openWindow(id: "about")
                }
            }

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appUpdater.checkForUpdates()
                }
                .disabled(!appUpdater.isConfigured || !appUpdater.canCheckForUpdates)
            }
        }

        Window("About Fan Curve", id: "about") {
            AboutContentView()
                .environmentObject(appUpdater)
                .frame(minWidth: 560, idealWidth: 620, minHeight: 420, idealHeight: 500)
        }
        .defaultSize(width: 620, height: 500)
        .windowResizability(.contentSize)

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(agentClient)
                .environmentObject(curveModel)
                .environmentObject(appUpdater)
        }
        .defaultSize(width: 720, height: 620)
        .windowResizability(.contentMinSize)
    }

    private func handleTermination() {
        let store = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
        guard !store.bool(forKey: SharedConfigKeys.applyInBackground) else { return }
        Task {
            do {
                try await agentClient.setFanControlEnabled(false)
                store.set(false, forKey: SharedConfigKeys.curveActive)
            } catch {
                log.notice(
                    "app.termination.fan_control_disable_failed error=\(error.localizedDescription, privacy: .public) recovery=leave-agent-state"
                )
            }
        }
    }
}
