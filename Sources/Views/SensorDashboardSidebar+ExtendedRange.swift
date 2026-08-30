//
//  SensorDashboardSidebar+ExtendedRange.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-08-30.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

extension SensorDashboardSidebar {
  struct ExtendedRangeControls: View {
    @Binding var overdrive: Bool
    @Binding var underdrive: Bool

    @State private var confirmOverdrive = false
    @State private var confirmUnderdrive = false

    var body: some View {
      VStack(spacing: SensorDashboardSidebarConstants.controlsVStackSpacing) {
        extendedRangeToggle(
          title: "Enable Overdrive",
          warning: overdriveWarningText,
          isOn: overdriveBinding,
          accessibilityIdentifier: AppAccessibilityIdentifier.Dashboard.overdrive
        )
        extendedRangeToggle(
          title: "Enable Underdrive",
          warning: underdriveWarningText,
          isOn: underdriveBinding,
          accessibilityIdentifier: AppAccessibilityIdentifier.Dashboard.underdrive
        )
      }
      .alert("Enable Overdrive?", isPresented: $confirmOverdrive) {
        Button("Enable", role: .destructive) {
          sensorDashboardSidebarViewLog.notice("sidebar.overdrive.confirmed enabled=true")
          overdrive = true
        }
        Button("Cancel", role: .cancel) {
          confirmOverdrive = false
        }
      } message: {
        Text(overdriveWarningText)
      }
      .alert("Enable Underdrive?", isPresented: $confirmUnderdrive) {
        Button("Enable", role: .destructive) {
          sensorDashboardSidebarViewLog.notice("sidebar.underdrive.confirmed enabled=true")
          underdrive = true
        }
        Button("Cancel", role: .cancel) {
          confirmUnderdrive = false
        }
      } message: {
        Text(underdriveWarningText)
      }
    }

    private func extendedRangeToggle(
      title: String,
      warning: String,
      isOn: Binding<Bool>,
      accessibilityIdentifier: String
    ) -> some View {
      HStack {
        Label {
          Text(title)
            .font(.body)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(Color(nsColor: .systemOrange))
            .accessibilityHidden(true)
        }
        Spacer()
        Toggle("", isOn: isOn)
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.regular)
          .tint(Color.accentColor)
          .help(warning)
          .accessibilityLabel(title)
          .accessibilityHint(warning)
          .accessibilityValue(isOn.wrappedValue ? "1" : "0")
          .accessibilityIdentifier(accessibilityIdentifier)
      }
    }

    private var overdriveBinding: Binding<Bool> {
      Binding(
        get: { overdrive },
        set: { enabled in
          if enabled {
            confirmOverdrive = true
          } else {
            sensorDashboardSidebarViewLog.notice("sidebar.overdrive.toggled enabled=false")
            overdrive = false
          }
        }
      )
    }

    private var underdriveBinding: Binding<Bool> {
      Binding(
        get: { underdrive },
        set: { enabled in
          if enabled {
            confirmUnderdrive = true
          } else {
            sensorDashboardSidebarViewLog.notice("sidebar.underdrive.toggled enabled=false")
            underdrive = false
          }
        }
      )
    }

    private var overdriveWarningText: String {
      "Overdrive pushes fan targets beyond the firmware reported max. "
        + "Sustained high RPM shortens bearing life and increases noise. "
        + "Only enable if you accept the tradeoff."
    }

    private var underdriveWarningText: String {
      "Underdrive lets the curve force fans to 0 RPM in manual mode. "
        + "Without airflow your machine can overheat under load and throttle or shut down. "
        + "Only enable if you know your thermal limits."
    }
  }
}
