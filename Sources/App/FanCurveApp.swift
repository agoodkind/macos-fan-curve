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
  @StateObject private var xpcClient = XPCClient()
  @StateObject private var curveModel = FanCurveModel()
  @StateObject private var appUpdater = AppUpdater()

  init() {
    AppLog.bootstrap(subsystem: "io.goodkind.fan")
    // First-run default for the background control preference. Keeping
    // this true preserves existing behavior where the agent continues
    // after the app closes.
    let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
    if suite.object(forKey: SharedConfigKeys.applyInBackground) == nil {
      suite.set(true, forKey: SharedConfigKeys.applyInBackground)
    }

    // Every write to the shared suite in this process pings the Agent
    // via Darwin notification so it can apply the change within a few
    // milliseconds instead of waiting for its next 1 Hz tick.
    NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: suite,
      queue: .main
    ) { _ in
      SharedConfigPush.post()
    }

    // When the user quits the app and background control is off, clear
    // the active flag so the agent resets fans to auto on its next tick.
    NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { _ in
      let store = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
      if !store.bool(forKey: SharedConfigKeys.applyInBackground) {
        store.set(false, forKey: SharedConfigKeys.curveActive)
        SharedConfigPush.post()
      }
    }
  }

  @Environment(\.openWindow) private var openWindow

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(xpcClient)
        .environmentObject(curveModel)
        .environmentObject(appUpdater)
    }
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
        .environmentObject(xpcClient)
        .environmentObject(curveModel)
        .environmentObject(appUpdater)
    }
    .defaultSize(width: 720, height: 620)
    .windowResizability(.contentMinSize)
  }
}
