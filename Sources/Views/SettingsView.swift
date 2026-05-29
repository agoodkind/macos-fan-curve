//
//  SettingsView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import AppKit
import AppLog
import SwiftUI

private let settingsViewLog = AppLog.make(category: "SettingsView")

private enum SettingsWindowConstants {
    static let minWidth: CGFloat = 520
    static let minHeight: CGFloat = 460
}

/// Root Settings window. Uses the macOS Settings scene (Cmd-comma).
/// Three tabs ordered by how often a user reaches for them. Profiles is
/// the hero since it holds the curve itself. General covers everything
/// that runs outside the foreground app. About carries meta information.
struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @StateObject private var renderActivity = WindowRenderActivity(windowTitle: "Settings")

    var body: some View {
        TabView(selection: $selectedTab) {
            tabContent(for: .general, title: "General", systemImage: "gearshape") {
                GeneralSettingsView(monitoringGate: monitoringGate)
            }
            tabContent(for: .profiles, title: "Profiles", systemImage: "chart.xyaxis.line") {
                ProfilesSettingsView()
            }
            tabContent(for: .advanced, title: "Advanced", systemImage: "slider.horizontal.3") {
                AdvancedSettingsView()
            }
            tabContent(for: .about, title: "About", systemImage: "info.circle") {
                AboutSettingsView()
            }
        }
        .frame(
            minWidth: SettingsWindowConstants.minWidth, minHeight: SettingsWindowConstants.minHeight
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowRenderActivityAttachment(activity: renderActivity))
        .onAppear {
            renderActivity.start()
        }
        .onDisappear {
            renderActivity.stop()
        }
    }

    private var monitoringGate: SettingsMonitoringGate {
        SettingsMonitoringGate(
            selectedTab: selectedTab,
            renderMode: renderActivity.mode
        )
    }

    @ViewBuilder
    private func tabContent<Content: View>(
        for tab: SettingsTab,
        title: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        SettingsTabHost(tab: tab, selectedTab: selectedTab, content: content)
            .tag(tab)
            .tabItem { Label(title, systemImage: systemImage) }
    }
}

private struct WindowRenderActivityAttachment: NSViewRepresentable {
    let activity: WindowRenderActivity

    func makeNSView(context _: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.activity = activity
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentView, context _: Context) {
        nsView.activity = activity
        nsView.attachCurrentWindow()
    }
}

private final class WindowAttachmentView: NSView {
    weak var activity: WindowRenderActivity?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachCurrentWindow()
    }

    func attachCurrentWindow() {
        settingsViewLog.debug(
            "settings.window_attachment.refresh has_window=\((window != nil), privacy: .public)"
        )
        Task { @MainActor [weak self] in
            self?.activity?.attach(window: self?.window)
        }
    }
}

private struct SettingsTabHost<Content: View>: View {
    let tab: SettingsTab
    let selectedTab: SettingsTab
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if selectedTab == tab {
                content()
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
    }
}
