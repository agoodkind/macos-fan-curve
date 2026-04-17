//
//  FanCurveApp.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import SwiftUI

@main
struct FanCurveApp: App {
  @StateObject private var xpcClient = XPCClient()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(xpcClient)
    }
  }
}
