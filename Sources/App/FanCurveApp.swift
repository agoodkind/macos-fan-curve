//
//  FanCurveApp.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import SwiftUI

private let log = AppLog.make(category: "AgentMain")

private enum WindowConstants {
    static let mainWindowWidth: CGFloat = 980
    static let mainWindowHeight: CGFloat = 540

    static let aboutWindowMinWidth: CGFloat = 560
    static let aboutWindowIdealWidth: CGFloat = 620
    static let aboutWindowMinHeight: CGFloat = 420
    static let aboutWindowIdealHeight: CGFloat = 500

    static let settingsWindowWidth: CGFloat = 720
    static let settingsWindowHeight: CGFloat = 620
}

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
                    NotificationCenter.default.publisher(
                        for: NSApplication.willTerminateNotification)
                ) { _ in
                    handleTermination()
                }
        }
        .defaultSize(
            width: WindowConstants.mainWindowWidth, height: WindowConstants.mainWindowHeight
        )
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

            #if DEBUG
                CommandMenu("Debug") {
                    Button("Live (No Scenario)") {
                        DevScenarioStore.shared.current = nil
                    }
                    Divider()
                    ForEach(DevScenario.allCases) { scenario in
                        Button(scenario.menuTitle) {
                            DevScenarioStore.shared.current = scenario
                        }
                    }
                }
            #endif
        }

        Window("About Fan Curve", id: "about") {
            AboutContentView()
                .environmentObject(appUpdater)
                .frame(
                    minWidth: WindowConstants.aboutWindowMinWidth,
                    idealWidth: WindowConstants.aboutWindowIdealWidth,
                    minHeight: WindowConstants.aboutWindowMinHeight,
                    idealHeight: WindowConstants.aboutWindowIdealHeight
                )
        }
        .defaultSize(
            width: WindowConstants.aboutWindowIdealWidth,
            height: WindowConstants.aboutWindowIdealHeight
        )
        .windowResizability(.contentSize)

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(agentClient)
                .environmentObject(curveModel)
                .environmentObject(appUpdater)
        }
        .defaultSize(
            width: WindowConstants.settingsWindowWidth, height: WindowConstants.settingsWindowHeight
        )
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
