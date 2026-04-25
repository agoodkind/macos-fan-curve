//
//  ContentView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import SwiftUI

struct ContentView: View {
  @Environment(\.openWindow) private var openWindow
  @EnvironmentObject var xpcClient: XPCClient
  @EnvironmentObject var curveModel: FanCurveModel
  @StateObject private var installState = InstallationState()
  @StateObject private var runtimeState = AgentSnapshotState()

  @AppStorage("sidebarWidth") private var sidebarWidth: Double = 240
  @State private var dragStartWidth: Double? = nil

  private let minSidebarWidth: Double = 200
  private let maxSidebarWidth: Double = 400

  var body: some View {
    Group {
      if installState.step == .ready {
        mainLayout
      } else {
        OnboardingView(state: installState)
      }
    }
    .frame(minWidth: 820, idealWidth: 980, minHeight: 620, idealHeight: 680)
    .background(Color(nsColor: .windowBackgroundColor))
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        settingsToolbarButton
      }
    }
    .onAppear {
      installState.startMonitoring(xpcClient: xpcClient)
      runtimeState.start()
    }
    .onDisappear {
      installState.stopMonitoring()
      runtimeState.stop()
    }
  }

  private var settingsToolbarButton: some View {
    Button {
      openWindow(id: "settings")
    } label: {
      Image(systemName: "gearshape")
    }
    .help("Settings")
  }

  private var mainLayout: some View {
    HStack(spacing: 0) {
      FanCurveEditor(model: curveModel, runtime: runtimeState)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)

      sidebarSplitter

      SensorDashboard(
        runtime: runtimeState,
        curveModel: curveModel,
        installState: installState
      )
      .frame(width: sidebarWidth)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
