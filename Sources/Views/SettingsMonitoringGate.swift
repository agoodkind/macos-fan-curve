//
//  SettingsMonitoringGate.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-24.
//  Copyright © 2026
//

struct SettingsMonitoringGate: Equatable {
    let selectedTab: SettingsTab
    let renderMode: AppRenderMode

    var isMonitoringEnabled: Bool {
        selectedTab == .general && renderMode == .interactive
    }
}
