//
//  FanCurveApp.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import ServiceManagement
import SwiftUI

@main
struct FanCurveApp: App {
  @StateObject private var xpcClient = XPCClient()

  init() {
    registerAgent()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(xpcClient)
    }
  }

  /// Register the LaunchAgent via SMAppService on launch. Idempotent.
  private func registerAgent() {
    guard #available(macOS 13.0, *) else {
      Log.info("SMAppService unavailable on this macOS, skipping agent registration")
      return
    }
    let service = SMAppService.agent(plistName: "\(generatedAgentBundleID).plist")
    do {
      try service.register()
      Log.info("FanCurve agent registered (status \(service.status.rawValue))")
    } catch {
      Log.debug("Agent registration failed (may already be registered): \(error)")
    }
  }
}
