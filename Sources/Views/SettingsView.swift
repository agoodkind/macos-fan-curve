//
//  SettingsView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import SwiftUI

/// Root Settings window. Uses the macOS Settings scene (Cmd-comma).
/// Three tabs ordered by how often a user reaches for them. Profiles is
/// the hero since it holds the curve itself. General covers everything
/// that runs outside the foreground app. About carries meta information.
struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tag(SettingsTab.general)
                .tabItem { Label("General", systemImage: "gearshape") }
            ProfilesSettingsView()
                .tag(SettingsTab.profiles)
                .tabItem { Label("Profiles", systemImage: "chart.xyaxis.line") }
            AdvancedSettingsView()
                .tag(SettingsTab.advanced)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            AboutSettingsView()
                .tag(SettingsTab.about)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 520, minHeight: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            selectedTab = .general
        }
    }
}
