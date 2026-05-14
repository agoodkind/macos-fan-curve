//
//  ContentView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import AppLog
import SwiftUI

private let contentViewLog = AppLog.make(category: "ContentView")

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var agentClient: FanCurveAgentClient
    @EnvironmentObject var curveModel: FanCurveModel
    @StateObject private var installState = InstallationState()
    @StateObject private var renderActivity = AppRenderActivity()

    @AppStorage("sidebarWidth") private var sidebarWidth: Double = 240

    private let mainWindowHeight: CGFloat = 540
    private let dashboardTransitionAnimation = Animation.easeInOut(duration: 0.18)
    private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

    @AppStorage(SharedConfigKeys.boostEnabled, store: suite)
    private var boostEnabled: Bool = false

    var body: some View {
        Group {
            if showsDashboardArea {
                dashboardContent
            } else {
                OnboardingView(state: installState)
            }
        }
        .frame(
            minWidth: 820,
            idealWidth: 980,
            maxWidth: .infinity,
            minHeight: mainWindowHeight,
            idealHeight: mainWindowHeight,
            maxHeight: .infinity
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .topTrailing) {
            #if DEBUG
                if FrameProfiler.isEnabledByLaunchConfiguration {
                    if renderActivity.mode.showsLiveDashboard {
                        ZStack(alignment: .topTrailing) {
                            FrameProfilerMetalProbe(renderMode: renderActivity.mode)
                                .frame(width: 1, height: 1)
                                .allowsHitTesting(false)

                            FrameProfilerOverlay(renderMode: renderActivity.mode)
                                .padding(10)
                        }
                    }
                }
            #endif
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                settingsToolbarButton
            }
        }
        .onAppear {
            renderActivity.start()
            #if DEBUG
                FrameProfiler.shared.setSamplingActive(renderActivity.mode == .interactive)
            #endif
            contentViewLog.notice(
                "content_view.appeared installation_step=\(String(describing: installState.step), privacy: .public) ready=\(fanControlReady, privacy: .public) dashboard_area=\(showsDashboardArea, privacy: .public)"
            )
            agentClient.start()
            installState.startMonitoring(agentClient: agentClient)
        }
        .onChange(of: installState.step) { step in
            contentViewLog.notice(
                "content_view.installation_step.changed step=\(String(describing: step), privacy: .public) ready=\(fanControlReady, privacy: .public) dashboard_area=\(showsDashboardArea, privacy: .public)"
            )
        }
        .onChange(of: renderActivity.mode) { mode in
            #if DEBUG
                FrameProfiler.shared.setSamplingActive(mode == .interactive)
            #endif
        }
        .onDisappear {
            #if DEBUG
                FrameProfiler.shared.setSamplingActive(false)
            #endif
            renderActivity.stop()
            installState.stopMonitoring()
        }
        .onChange(of: curveModel.controlPoints) { _ in pushCurveToAgent(reason: "points-changed") }
        .onChange(of: curveModel.interpolationMode) { _ in pushCurveToAgent(reason: "mode-changed") }
    }

    private var settingsToolbarButton: some View {
        Button {
            openWindow(id: "settings")
        } label: {
            Image(systemName: "gearshape")
        }
        .help("Settings")
    }

    private var dashboardContent: some View {
        ZStack {
            if renderActivity.mode.showsLiveDashboard {
                LiveDashboardContent(
                    agentClient: agentClient,
                    curveModel: curveModel,
                    installState: installState,
                    renderMode: renderActivity.mode,
                    sidebarWidth: $sidebarWidth,
                    boostEnabled: boostEnabled
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 0.985))
                    )
                )
            } else {
                PausedDashboardView()
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.985)),
                            removal: .opacity
                        )
                    )
            }
        }
        .animation(dashboardTransitionAnimation, value: renderActivity.mode.showsLiveDashboard)
    }

    private var fanControlReady: Bool {
        installState.step == .ready
    }

    private var showsDashboardArea: Bool {
        switch installState.step {
        case .checking, .agentMissing, .agentAwaitingApproval:
            return false
        case .helperMissing, .helperAwaitingApproval, .ready:
            return true
        }
    }

    private func pushCurveToAgent(reason: String) {
        contentViewLog.info("content_view.curve.push requested reason=\(reason, privacy: .public)")
        Task {
            do {
                try await agentClient.setCurve(
                    points: curveModel.controlPoints,
                    interpolationMode: curveModel.interpolationMode
                )
            } catch {
                contentViewLog.notice(
                    "content_view.curve.push_failed reason=\(reason, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=agent-next-poll"
                )
            }
        }
    }
}

private struct LiveDashboardContent: View {
    @ObservedObject var agentClient: FanCurveAgentClient
    @ObservedObject var curveModel: FanCurveModel
    @ObservedObject var installState: InstallationState

    let renderMode: AppRenderMode
    @Binding var sidebarWidth: Double
    let boostEnabled: Bool

    @State private var dragStartWidth: Double?

    private let minSidebarWidth: Double = 200
    private let maxSidebarWidth: Double = 400

    var body: some View {
        HStack(spacing: 0) {
            FanCurveEditor(
                model: curveModel,
                runtime: agentClient,
                renderMode: renderMode,
                presentation: presentation
            )
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            sidebarSplitter

            SensorDashboard(
                runtime: agentClient,
                curveModel: curveModel,
                installState: installState,
                renderMode: renderMode,
                presentation: presentation
            )
            .frame(width: sidebarWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var presentation: DashboardPresentationState {
        DashboardPresentationState.make(
            installationStep: installState.step,
            telemetryFresh: agentClient.isFresh,
            runtimeTelemetryAvailable: agentClient.governingTemperature > 0 && !agentClient.fans.isEmpty,
            curveActive: curveModel.isActive,
            boostEnabled: boostEnabled
        )
    }

    /// Vertical splitter: a thin hairline with a wider invisible hit area.
    /// Shows the resize cursor on hover so the affordance is discoverable
    /// even though the visible line is only 0.5pt.
    private var sidebarSplitter: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: 10)
            Divider().opacity(0.15)
        }
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = sidebarWidth
                    }
                    let delta = -value.translation.width
                    let next = (dragStartWidth ?? sidebarWidth) + Double(delta)
                    sidebarWidth = max(minSidebarWidth, min(maxSidebarWidth, next))
                }
                .onEnded { _ in dragStartWidth = nil }
        )
    }
}

private struct PausedDashboardView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "pause.circle")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.secondary)

            Text("Dashboard Paused")
                .font(.headline)

            Text("Live rendering resumes when the window becomes active.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
