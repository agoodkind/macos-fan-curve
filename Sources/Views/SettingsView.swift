//
//  SettingsView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import ServiceManagement
import SwiftUI

/// Root Settings window. Uses the macOS Settings scene (Cmd-comma).
struct SettingsView: View {
  var body: some View {
    TabView {
      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape") }
      HelpersSettingsView()
        .tabItem { Label("Helpers", systemImage: "bolt.badge.clock") }
      UpdatesSettingsView()
        .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
    }
    .frame(width: 480, height: 360)
  }
}

/// General preferences: interpolation mode and temperature unit.
struct GeneralSettingsView: View {
  @AppStorage("interpolationMode") private var interpolationRaw: String = "catmullRom"
  @AppStorage("temperatureUnit") private var unitRaw: String = "celsius"

  var body: some View {
    Form {
      Section {
        Picker("Interpolation", selection: $interpolationRaw) {
          Text("Linear").tag("linear")
          Text("Smooth").tag("catmullRom")
        }
        .pickerStyle(.segmented)
      } header: {
        Text("Curve Interpolation")
      } footer: {
        Text("Linear draws straight segments between points. Smooth uses monotone cubic curves.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        Picker("Temperature Unit", selection: $unitRaw) {
          ForEach(TemperatureUnit.allCases) { unit in
            Text(unit.displayName).tag(unit.rawValue)
          }
        }
        .pickerStyle(.segmented)
      } header: {
        Text("Display")
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}

/// Helper and agent management.
struct HelpersSettingsView: View {
  @EnvironmentObject var xpcClient: XPCClient
  @StateObject private var state = InstallationState()

  var body: some View {
    Form {
      Section {
        helperRow
      } header: {
        Text("Privileged Helper")
      } footer: {
        Text("Reads and writes SMC keys as root. Required for fan control.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        agentRow
      } header: {
        Text("Background Agent")
      } footer: {
        Text("Applies the curve when the app is closed. Resets fans to auto when disabled.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding()
    .onAppear { state.startMonitoring(xpcClient: xpcClient) }
    .onDisappear { state.stopMonitoring() }
  }

  private var helperRow: some View {
    HStack {
      statusDot(ok: state.helperReachable)
      Text("smcfanhelper")
        .font(.body)
      Spacer()
      Text(state.helperReachable ? "Running" : "Not running")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var agentRow: some View {
    HStack {
      statusDot(ok: state.agentEnabled)
      VStack(alignment: .leading) {
        Text("fancurveagent")
          .font(.body)
        Text(state.agentStatusLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if state.agentEnabled {
        Button("Uninstall") { state.unregisterAgent() }
          .controlSize(.small)
      } else {
        Button("Install") { state.registerAgent() }
          .controlSize(.small)
      }
    }
  }

  @ViewBuilder
  private func statusDot(ok: Bool) -> some View {
    Circle()
      .fill(ok ? Color(nsColor: .systemGreen) : Color(nsColor: .systemGray))
      .frame(width: 8, height: 8)
  }
}

/// Updates preferences. Currently a stub. Sparkle can be added later.
struct UpdatesSettingsView: View {
  @AppStorage("autoCheckUpdates") private var autoCheck: Bool = true

  var body: some View {
    Form {
      Section {
        Toggle("Automatically check for updates", isOn: $autoCheck)
        Button("Check Now") {
          NSWorkspace.shared.open(URL(string: "https://github.com/agoodkind/macos-fan-curve/releases")!)
        }
      } header: {
        Text("Software Updates")
      } footer: {
        Text("Update checks are not yet automated in this build. The button opens the releases page.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        Text("Build \(generatedGitVersion)")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("About")
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}
