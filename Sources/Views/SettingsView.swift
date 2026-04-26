//
//  SettingsView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import AppLog
import CryptoKit
import ServiceManagement

private let log = AppLog.make(category: "SettingsView")
import SwiftUI

private enum SettingsTab: Hashable {
  case general
  case profiles
  case advanced
  case about
}

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

/// General display preferences. Stored in UserDefaults.standard because they
/// only affect the GUI and do not need to be visible to the agent.
struct GeneralSettingsView: View {
  @AppStorage("temperatureUnit") private var unitRaw: String = "celsius"

  private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

  @AppStorage(SharedConfigKeys.applyInBackground, store: suite)
  private var applyInBackground: Bool = true

  @EnvironmentObject var xpcClient: XPCClient
  @StateObject private var installState = InstallationState()
  @StateObject private var ownershipStatus = FanOwnershipStatus()
  @State private var showOwnership = false

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
        Text("Only affects how temperatures are displayed.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        Toggle("Apply curve in background", isOn: $applyInBackground)
      } header: {
        Text("Background Control")
      } footer: {
        Text(
          "When on, the curve keeps controlling fans after you quit the app and resumes on next login. When off, quitting returns fans to system auto."
        )
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

      Section {
        helperRow
        DisclosureGroup(isExpanded: $showOwnership) {
          ownershipContent
        } label: {
          ownershipSummary
        }
      } header: {
        Text("Privileged Helper")
      } footer: {
        Text(
          "Reads and writes SMC keys as root. Required for fan control. The helper arbitrates between fan writers by priority; current owners show above."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .onAppear {
      installState.startMonitoring(xpcClient: xpcClient)
    }
    .onDisappear {
      installState.stopMonitoring()
      ownershipStatus.stopMonitoring()
    }
    .onChange(of: showOwnership) { nowShowing in
      if nowShowing {
        ownershipStatus.startMonitoring(intervalSeconds: 1.5)
      } else {
        ownershipStatus.stopMonitoring()
      }
    }
  }

  private var ownershipSummary: some View {
    let count = ownershipStatus.rows.count
    let label: String = {
      if !showOwnership && !ownershipStatus.hasLoaded { return "Current Owners" }
      if ownershipStatus.isMonitoring && !ownershipStatus.hasLoaded { return "Current Owners (checking helper...)" }
      if !ownershipStatus.reachable { return "Current Owners (helper unreachable)" }
      if count == 0 { return "Current Owners (no fans claimed)" }
      return "Current Owners (\(count) claimed)"
    }()
    return Text(label).font(.caption)
  }

  @ViewBuilder
  private var ownershipContent: some View {
    if ownershipStatus.isMonitoring && !ownershipStatus.hasLoaded {
      Text("Checking helper...")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else
    if ownershipStatus.rows.isEmpty {
      Text(ownershipStatus.reachable ? "No fans currently claimed." : "Waiting for helper.")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else {
      ForEach(ownershipStatus.rows) { row in
        ownershipRow(row)
      }
    }
  }

  @ViewBuilder
  private func ownershipRow(_ row: ArbiterRow) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Fan \(row.fanIndex)")
          .font(.caption)
        Text("owned by \(row.clientName)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text("priority \(row.priority)")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
        Text(formatAge(row.ageSeconds))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
      }
    }
  }

  private func formatAge(_ seconds: TimeInterval) -> String {
    if seconds < 1.0 { return "just now" }
    if seconds < 60 { return "\(Int(seconds))s ago" }
    let minutes = Int(seconds / 60)
    return "\(minutes)m ago"
  }

  private var helperRow: some View {
    HStack {
      statusDot(ok: installState.helperReachable)
      VStack(alignment: .leading, spacing: 2) {
        Text("SMC Fan Helper")
          .font(.body)
        Text("smcfanhelper")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text(installState.helperReachable ? "Running" : "Stopped")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var agentRow: some View {
    HStack(alignment: .center) {
      agentStatusDot
      VStack(alignment: .leading, spacing: 2) {
        Text("Fan Curve Agent")
          .font(.body)
        Text(agentSubtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer()
      if installState.agentEnabled, !installState.agentLive {
        Button("Restart") { restartAgent() }
          .controlSize(.small)
      } else if installState.agentEnabled {
        Text("Installed")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Button("Install") { installState.registerAgent() }
          .controlSize(.small)
      }
    }
  }

  private var agentSubtitle: String {
    if !installState.agentEnabled { return "Not installed" }
    if !installState.agentLive {
      if !installState.agentLastError.isEmpty {
        return "Stopped: \(installState.agentLastError)"
      }
      return "Process stopped. Click Restart to relaunch."
    }
    return "Healthy"
  }

  /// Unregister then register the agent to force a fresh launch. macOS
  /// launchd will not relaunch a crashed SMAppService.agent on its own;
  /// only re-registration starts a new process.
  private func restartAgent() {
    installState.unregisterAgent()
    installState.registerAgent()
  }

  /// Three-state dot for the Agent. Green when live, orange when
  /// registered but not ticking (fan control is effectively dead), gray
  /// when unregistered.
  @ViewBuilder
  private var agentStatusDot: some View {
    let color: Color = {
      if installState.agentLive { return Color(nsColor: .systemGreen) }
      if installState.agentEnabled { return Color(nsColor: .systemOrange) }
      return Color(nsColor: .systemGray)
    }()
    Circle()
      .fill(color)
      .frame(width: 8, height: 8)
  }

  @ViewBuilder
  private func statusDot(ok: Bool) -> some View {
    Circle()
      .fill(ok ? Color(nsColor: .systemGreen) : Color(nsColor: .systemGray))
      .frame(width: 8, height: 8)
  }
}

/// Curve behavior settings. These live in the shared suite because the Agent
/// reads the same values when evaluating the curve in the background.
struct ProfilesSettingsView: View {
  @EnvironmentObject var curveModel: FanCurveModel
  @StateObject private var sensorState = SensorState()
  @EnvironmentObject var xpcClient: XPCClient

  @State private var showLearnSheet = false
  @State private var previewController: FanCurveController?

  private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

  @AppStorage(SharedConfigKeys.interpolationMode, store: suite)
  private var interpolationRaw: String = "catmullRom"

  @ViewBuilder
  private func presetRow(_ preset: CurvePreset) -> some View {
    Button {
      curveModel.controlPoints = preset.curvePoints()
    } label: {
      HStack(alignment: .center, spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(preset.name)
            .font(.body)
            .foregroundStyle(.primary)
          Text(preset.subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  var body: some View {
    ScrollView {
      formBody
    }
    .sheet(isPresented: $showLearnSheet, onDismiss: stopPreviewPoller) {
      LearnSheet(curveModel: curveModel, sensorState: sensorState)
        .onAppear(perform: startPreviewPoller)
    }
  }

  private var formBody: some View {
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
        ForEach(CurvePresets.all) { preset in
          presetRow(preset)
        }
      } header: {
        Text("Presets")
      } footer: {
        Text("Applying a preset replaces your current curve. You can edit the points again afterward.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        Button {
          log.info("curve.reset.tapped pointsBefore=\(curveModel.controlPoints.count, privacy: .public)")
          curveModel.resetToDefault()
          log.info("curve.reset.done pointsAfter=\(curveModel.controlPoints.count, privacy: .public)")
        } label: {
          Label("Reset to Default Curve", systemImage: "arrow.counterclockwise")
        }
      } header: {
        Text("Reset")
      } footer: {
        Text("Replaces the current curve with the built-in starting curve.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        Button {
          showLearnSheet = true
        } label: {
          Label("Learn from Current System", systemImage: "brain.head.profile")
        }
      } header: {
        Text("Learn")
      } footer: {
        Text(
          "Samples your machine under load and fits a curve that mirrors how macOS runs it in Auto mode."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

    }
    .formStyle(.grouped)
  }

  /// Spin up a read-only sensor poller so the LearnSheet can display live
  /// temperatures and fan RPMs while sampling.
  private func startPreviewPoller() {
    let ctrl = FanCurveController(xpcClient: xpcClient, sensorState: sensorState)
    previewController = ctrl
    ctrl.start()
  }

  private func stopPreviewPoller() {
    previewController?.stop()
    previewController = nil
  }
}

/// About the app. Checks the GitHub releases API for the latest tag and
/// shows author links. Formerly called "Updates".
struct AboutSettingsView: View {
  var body: some View {
    AboutContentView()
  }
}

/// Shared About pane. Used both as the Settings > About tab and as the
/// standalone About window that replaces macOS's default panel. Keeps
/// version, update check, author, and build hashes in one place.
struct AboutContentView: View {
  @EnvironmentObject private var appUpdater: AppUpdater

  var body: some View {
    Form {
      Section {
        Toggle(
          "Automatically check for updates",
          isOn: Binding(
            get: { appUpdater.automaticallyChecksForUpdates },
            set: { appUpdater.setAutomaticallyChecksForUpdates($0) }))
        .disabled(!appUpdater.isConfigured)

        if appUpdater.isConfigured {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Label(updateStatusLabel, systemImage: updateStatusIcon)
                .foregroundColor(statusColor)
                .symbolRenderingMode(.hierarchical)
              Text("Updates are delivered automatically from goodkind.io.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Check Now") { appUpdater.checkForUpdates() }
              .disabled(!appUpdater.canCheckForUpdates)
          }
        } else {
          Label("Software updates are available in release builds.", systemImage: "hammer")
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
        }
      } header: {
        Text("Software Updates")
      }

      Section {
        HStack(alignment: .center, spacing: 12) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Alex Goodkind")
              .font(.body.weight(.semibold))
            Text("alex@goodkind.io")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            NSWorkspace.shared.open(URL(string: "mailto:alex@goodkind.io")!)
          } label: {
            Label("Email", systemImage: "envelope.fill")
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.bordered)
          .controlSize(.regular)
          .help("Email alex@goodkind.io")
          .accessibilityLabel("Email")

          Button {
            NSWorkspace.shared.open(URL(string: "https://goodkind.io")!)
          } label: {
            Label("Website", systemImage: "globe")
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.bordered)
          .controlSize(.regular)
          .help("Open goodkind.io")
          .accessibilityLabel("Website")

          Button {
            NSWorkspace.shared.open(URL(string: "https://github.com/agoodkind")!)
          } label: {
            Label("Source", systemImage: "chevron.left.forwardslash.chevron.right")
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.bordered)
          .controlSize(.regular)
          .help("Open GitHub profile")
          .accessibilityLabel("Source")
        }

        buildInfoRow(label: "Version", value: versionLine)
        buildInfoRow(label: "Binaries", value: binariesLine)
      } header: {
        Text("About")
      }
    }
    .formStyle(.grouped)
  }

  private var updateStatusLabel: String {
    if appUpdater.canCheckForUpdates { return "Automatic updates are on" }
    return "Updater is starting"
  }

  /// Single-line version summary. Matches the compact style used by
  /// lm-review and agent-gate in their logs: version, commit, branch,
  /// and build date separated by middle dots.
  private var versionLine: String {
    let version = generatedGitVersion
      .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
    return "\(version) · \(generatedGitBranch) · built \(generatedBuildDate)"
  }

  /// Compact hash pairing for the app and agent binaries.
  private var binariesLine: String {
    "app \(BuildHashes.appHash) · agent \(BuildHashes.agentHash)"
  }

  /// One line in the About section for a labeled build attribute. Uses
  /// a monospaced value so hashes and dates align.
  @ViewBuilder
  private func buildInfoRow(label: String, value: String) -> some View {
    HStack {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }

  private var updateStatusIcon: String {
    "arrow.triangle.2.circlepath.circle"
  }

  private var statusColor: Color {
    Color(nsColor: .systemBlue)
  }
}

/// Advanced risk-gated settings. Overdrive and Underdrive push beyond the
/// firmware reported safe range. Load Floor raises fans preemptively
/// under CPU load. All three share the "power user" framing.
struct AdvancedSettingsView: View {
  private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

  @AppStorage(SharedConfigKeys.overdriveEnabled, store: suite)
  private var overdrive: Bool = false

  @AppStorage(SharedConfigKeys.underdriveEnabled, store: suite)
  private var underdrive: Bool = false

  @AppStorage(SharedConfigKeys.curveNormalPriority, store: suite)
  private var curveNormalPriority: Double = 10

  @AppStorage(SharedConfigKeys.userBoostPriority, store: suite)
  private var userBoostPriority: Double = 50

  @State private var confirmOverdrive = false
  @State private var confirmUnderdrive = false

  private var overdriveBinding: Binding<Bool> {
    Binding(
      get: { overdrive },
      set: { newValue in
        if newValue { confirmOverdrive = true } else { overdrive = false }
      })
  }

  private var underdriveBinding: Binding<Bool> {
    Binding(
      get: { underdrive },
      set: { newValue in
        if newValue { confirmUnderdrive = true } else { underdrive = false }
      })
  }

  var body: some View {
    ScrollView {
      Form {
        Section {
          LoadAssistModuleView(kind: .cpu)
          LoadAssistModuleView(kind: .gpu)
        } header: {
          Text("Load Assist")
        } footer: {
          Text(
            "Each assist curve maps load percent to a minimum fan floor. The agent evaluates the temperature curve, CPU assist, and GPU assist, then applies whichever result is highest."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Section {
          prioritySliderRow(
            title: "Normal curve",
            value: $curveNormalPriority,
            help:
              "Priority used for normal curve writes. Higher values preempt lower-priority fan clients.")
          prioritySliderRow(
            title: "When boost is on",
            value: $userBoostPriority,
            help:
              "Priority used while Boost is active. Raise it above competing fan apps if Boost should win.")
        } header: {
          Text("Client Priority")
        } footer: {
          Text(
            "Priority the agent uses when writing fans. Higher values preempt lower. Defaults match other fan aware apps: normal curve at 10, boost at 50. Raise boost above 50 if you want boost to preempt an active lmd LLM run."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Section {
          Toggle(isOn: overdriveBinding) {
            VStack(alignment: .leading, spacing: 2) {
              Text("Overdrive")
              Text(
                "100% on the curve requests \(Int(overdriveTargetRPM)) RPM. Fans can wear faster."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }

          Toggle(isOn: underdriveBinding) {
            VStack(alignment: .leading, spacing: 2) {
              Text("Underdrive")
              Text(
                "0% writes 0 RPM in manual mode. Fans can stop completely and the machine can overheat."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
        } header: {
          Label {
            Text("Expanded Range")
          } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(Color(nsColor: .systemOrange))
          }
        } footer: {
          Text(
            "These modes bypass the firmware reported safe range. Enable them only if you understand the risks."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .padding()
    }
    .alert("Enable Overdrive?", isPresented: $confirmOverdrive) {
      Button("Enable", role: .destructive) { overdrive = true }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Overdrive pushes fan targets beyond the firmware reported max. Sustained high RPM shortens bearing life and increases noise. Only enable if you accept the tradeoff."
      )
    }
    .alert("Enable Underdrive?", isPresented: $confirmUnderdrive) {
      Button("Enable", role: .destructive) { underdrive = true }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Underdrive lets the curve force fans to 0 RPM in manual mode. Without airflow your machine can overheat under load and throttle or shut down. Only enable if you know your thermal limits."
      )
    }
  }

  @ViewBuilder
  private func prioritySliderRow(title: String, value: Binding<Double>, help: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center) {
        Text(title)
        Spacer()
        Text("\(Int(value.wrappedValue.rounded()))")
          .font(.system(.body, design: .rounded).weight(.semibold))
          .monospacedDigit()
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(
            Capsule()
              .fill(Color.primary.opacity(0.07))
          )
      }
      Slider(
        value: Binding(
          get: { value.wrappedValue },
          set: { value.wrappedValue = $0.rounded() }
        ),
        in: 1...100
      )
      .help(help)
    }
  }
}

/// Computes SHA256 short fingerprints of the main app and embedded agent
/// binaries. Cached in static properties so the About tab does not
/// re-hash on every render.
enum BuildHashes {
  static let appHash: String = shortHash(of: Bundle.main.executableURL)
  static let agentHash: String = shortHash(
    of: Bundle.main.bundleURL
      .appendingPathComponent("Contents/MacOS/\(generatedAgentExecutableName)"))

  private static func shortHash(of url: URL?) -> String {
    guard let url, let data = try? Data(contentsOf: url) else { return "n/a" }
    let digest = SHA256.hash(data: data)
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return String(hex.prefix(12))
  }
}
