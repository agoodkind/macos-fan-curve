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
      CurveSettingsView()
        .tabItem { Label("Curve", systemImage: "waveform.path.ecg") }
      HelpersSettingsView()
        .tabItem { Label("Helpers", systemImage: "bolt.badge.clock") }
      UpdatesSettingsView()
        .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
    }
    .frame(width: 520, height: 420)
  }
}

/// General display preferences. Stored in UserDefaults.standard because they
/// only affect the GUI and do not need to be visible to the agent.
struct GeneralSettingsView: View {
  @AppStorage("temperatureUnit") private var unitRaw: String = "celsius"

  var body: some View {
    Form {
      Section {
        Picker("Temperature Unit", selection: $unitRaw) {
          ForEach(TemperatureUnit.allCases) { unit in
            Text(unit.displayName).tag(unit.rawValue)
          }
        }
        .pickerStyle(.segmented)
      } header: {
        Text("Display")
      } footer: {
        Text("Curves are stored internally in Celsius. Changing this only affects the UI.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}

/// Curve behavior settings. These live in the shared suite because the Agent
/// reads the same values when evaluating the curve in the background.
struct CurveSettingsView: View {
  @StateObject private var curveModel = FanCurveModel()

  private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

  @AppStorage(SharedConfigKeys.interpolationMode, store: suite)
  private var interpolationRaw: String = "catmullRom"

  @AppStorage(SharedConfigKeys.overdriveEnabled, store: suite)
  private var overdrive: Bool = false

  var body: some View {
    Form {
      Section {
        Picker("Interpolation", selection: $interpolationRaw) {
          Text("Linear").tag("linear")
          Text("Smooth").tag("catmullRom")
        }
        .pickerStyle(.segmented)
      } header: {
        Text("Smoothing")
      } footer: {
        Text("Linear draws straight segments between points. Smooth uses monotone cubic.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        Toggle(isOn: $overdrive) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Overdrive")
            Text("100% on the curve requests \(Int(overdriveTargetRPM)) RPM")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      } header: {
        Text("Maximum Fan Speed")
      } footer: {
        Text(
          "The firmware reports a conservative max. Hardware can spin well past it when the target is higher."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section {
        Button(role: .destructive) {
          curveModel.resetToDefault()
        } label: {
          Label("Reset to Default Curve", systemImage: "arrow.counterclockwise")
        }
      } header: {
        Text("Danger Zone")
      } footer: {
        Text("Replaces your saved curve with the built-in default. This cannot be undone.")
          .font(.caption)
          .foregroundStyle(.secondary)
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

/// Updates settings. Checks the GitHub releases API for the latest tag.
struct UpdatesSettingsView: View {
  @AppStorage("autoCheckUpdates") private var autoCheck: Bool = true

  @StateObject private var checker = UpdateChecker()

  var body: some View {
    Form {
      Section {
        Toggle("Automatically check on launch", isOn: $autoCheck)

        HStack {
          Label(statusLabel, systemImage: statusIcon)
            .foregroundColor(statusColor)
            .symbolRenderingMode(.hierarchical)

          Spacer()

          Button("Check Now") {
            Task { await checker.check() }
          }
          .disabled(checker.isChecking)
        }

        if let latest = checker.latestTag, checker.isUpdateAvailable {
          Button {
            NSWorkspace.shared.open(
              URL(string: "https://github.com/agoodkind/macos-fan-curve/releases/tag/\(latest)")!)
          } label: {
            Label("Download \(latest)", systemImage: "arrow.down.circle.fill")
          }
          .buttonStyle(.borderedProminent)
        }
      } header: {
        Text("Software Updates")
      }

      Section {
        Text("Build \(generatedGitVersion)")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("Commit \(generatedGitCommit)")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("About")
      }
    }
    .formStyle(.grouped)
    .padding()
    .task {
      if autoCheck { await checker.check() }
    }
  }

  private var statusLabel: String {
    if checker.isChecking { return "Checking..." }
    if let err = checker.error { return "Error: \(err)" }
    if checker.isUpdateAvailable, let tag = checker.latestTag {
      return "Update available: \(tag)"
    }
    if checker.latestTag != nil { return "You are up to date" }
    return "Not checked yet"
  }

  private var statusIcon: String {
    if checker.isChecking { return "arrow.triangle.2.circlepath" }
    if checker.error != nil { return "exclamationmark.triangle" }
    if checker.isUpdateAvailable { return "arrow.down.circle.fill" }
    if checker.latestTag != nil { return "checkmark.circle.fill" }
    return "questionmark.circle"
  }

  private var statusColor: Color {
    if checker.error != nil { return Color(nsColor: .systemOrange) }
    if checker.isUpdateAvailable { return Color(nsColor: .systemBlue) }
    if checker.latestTag != nil { return Color(nsColor: .systemGreen) }
    return .secondary
  }
}

/// Polls the GitHub releases API. Not a full Sparkle replacement. Sufficient
/// for this project until auto-update is needed.
@MainActor
final class UpdateChecker: ObservableObject {
  @Published var latestTag: String?
  @Published var isUpdateAvailable = false
  @Published var isChecking = false
  @Published var error: String?

  private let releasesURL = URL(
    string: "https://api.github.com/repos/agoodkind/macos-fan-curve/releases/latest")!

  func check() async {
    isChecking = true
    error = nil
    defer { isChecking = false }

    do {
      var req = URLRequest(url: releasesURL)
      req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
      let (data, _) = try await URLSession.shared.data(for: req)
      let decoded = try JSONDecoder().decode(Release.self, from: data)
      latestTag = decoded.tagName
      isUpdateAvailable = compareVersion(decoded.tagName, against: generatedGitVersion)
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func compareVersion(_ latest: String, against current: String) -> Bool {
    // Strip leading 'v' if present, then compare as version-sortable strings.
    // Any mismatch counts as an update; precise semver comparison is overkill here.
    let l = latest.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
    let c = current.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
    return l != c && !c.contains(l)
  }

  private struct Release: Decodable {
    let tagName: String

    enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
  }
}
