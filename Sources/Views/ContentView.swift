//
//  ContentView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import SwiftUI

private let contentViewLog = AppLog.make(category: "ContentView")

// MARK: - Constants

private enum ContentViewConstants {
  // Main window geometry
  static let windowMinWidth: CGFloat = 820
  static let windowIdealWidth: CGFloat = 980
  static let windowHeight: CGFloat = 660

  // Dashboard transition animation
  static let dashboardTransitionDuration: TimeInterval = 0.18
  static let dashboardTransitionScale: CGFloat = 0.985

  // Default sidebar width (persisted via AppStorage)
  static let sidebarWidthDefault: Double = 240

  // Frame profiler overlay padding
  static let frameProfilerOverlayPadding: CGFloat = 10
}

private enum LiveDashboardConstants {
  // Sidebar resize constraints
  static let sidebarMinWidth: Double = 200
  static let sidebarMaxWidth: Double = 400

  // Fan curve editor inset
  static let curveEditorPadding: CGFloat = 16

  // Sidebar splitter hit-area width and divider opacity
  static let splitterHitAreaWidth: CGFloat = 10
  static let splitterDividerOpacity: Double = 0.15
}

private enum PausedDashboardConstants {
  // Pause icon size and spacing
  static let pauseIconSize: CGFloat = 36
  static let contentSpacing: CGFloat = 10
}

struct ContentView: View {
  @Environment(\.openWindow) private var openWindow
  @EnvironmentObject var agentClient: FanCurveAgentClient
  @EnvironmentObject var curveModel: FanCurveModel
  @StateObject private var installState = InstallationState()
  @StateObject private var renderActivity = AppRenderActivity()

  @AppStorage("sidebarWidth") private var sidebarWidth: Double = ContentViewConstants
    .sidebarWidthDefault

  private let mainWindowHeight: CGFloat = ContentViewConstants.windowHeight
  private let dashboardTransitionAnimation = Animation.easeInOut(
    duration: ContentViewConstants.dashboardTransitionDuration)
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
      minWidth: ContentViewConstants.windowMinWidth,
      idealWidth: ContentViewConstants.windowIdealWidth,
      maxWidth: .infinity,
      minHeight: mainWindowHeight,
      idealHeight: mainWindowHeight,
      maxHeight: .infinity
    )
    .background(Color(nsColor: .windowBackgroundColor))
    .accessibilityIdentifier(AppAccessibilityIdentifier.Application.mainWindow)
    .accessibilityValue(String(ProcessInfo.processInfo.processIdentifier))
    .overlay(alignment: .topTrailing) {
      #if DEBUG
        if FrameProfiler.isEnabledByLaunchConfiguration {
          if renderActivity.mode.showsLiveDashboard {
            ZStack(alignment: .topTrailing) {
              FrameProfilerMetalProbe(renderMode: renderActivity.mode)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)

              FrameProfilerOverlay(renderMode: renderActivity.mode)
                .padding(ContentViewConstants.frameProfilerOverlayPadding)
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
    .onChange(of: curveModel.interpolationMode) { _ in pushCurveToAgent(reason: "mode-changed")
    }
  }

  private var settingsToolbarButton: some View {
    Button {
      openWindow(id: "settings")
    } label: {
      Image(systemName: "gearshape")
    }
    .help("Settings")
    .accessibilityIdentifier(AppAccessibilityIdentifier.Application.settingsButton)
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
            removal: .opacity.combined(
              with: .scale(scale: ContentViewConstants.dashboardTransitionScale))
          )
        )
      } else {
        PausedDashboardView()
          .transition(
            .asymmetric(
              insertion: .opacity.combined(
                with: .scale(scale: ContentViewConstants.dashboardTransitionScale)),
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
    case .checking, .agentMissing, .agentAwaitingApproval, .helperAwaitingApproval:
      return false
    case .helperMissing:
      return installState.helperReachable
    case .ready:
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

  private let minSidebarWidth: Double = LiveDashboardConstants.sidebarMinWidth
  private let maxSidebarWidth: Double = LiveDashboardConstants.sidebarMaxWidth

  var body: some View {
    HStack(spacing: 0) {
      FanCurveEditor(
        model: curveModel,
        runtime: agentClient,
        renderMode: renderMode,
        presentation: presentation
      )
      .padding(LiveDashboardConstants.curveEditorPadding)
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
    .accessibilityIdentifier(AppAccessibilityIdentifier.Dashboard.root)
  }

  private var presentation: DashboardPresentationState {
    DashboardPresentationState.make(
      DashboardPresentationState.Inputs(
        installationStep: installState.step,
        telemetryFresh: agentClient.isFresh,
        runtimeTelemetryAvailable: agentClient.governingTemperature > 0
          && !agentClient.fans.isEmpty,
        helperReachable: agentClient.helperReachable,
        curveActive: curveModel.isActive,
        boostEnabled: boostEnabled
      )
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
        .frame(width: LiveDashboardConstants.splitterHitAreaWidth)
      Divider().opacity(LiveDashboardConstants.splitterDividerOpacity)
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
    VStack(spacing: PausedDashboardConstants.contentSpacing) {
      Image(systemName: "pause.circle")
        .font(.system(size: PausedDashboardConstants.pauseIconSize, weight: .regular))
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
