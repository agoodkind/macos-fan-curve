//
//  SettingsMonitoringGate.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-05-24.
//  Copyright © 2026, all rights reserved.
//

struct SettingsMonitoringGate: Equatable {
  let selectedTab: SettingsTab
  let renderMode: AppRenderMode

  var isMonitoringEnabled: Bool {
    selectedTab == .general && renderMode == .interactive
  }
}
