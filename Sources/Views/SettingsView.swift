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

/// Root Settings window. Uses the macOS Settings scene (Cmd-comma).
/// Three tabs ordered by how often a user reaches for them. Profiles is
/// the hero since it holds the curve itself. General covers everything
/// that runs outside the foreground app. About carries meta information.
struct SettingsView: View {
  var body: some View {
    TabView {
      ProfilesSettingsView()
        .tabItem { Label("Profiles", systemImage: "chart.xyaxis.line") }
      AdvancedSettingsView()
        .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape") }
      ArbiterSettingsView()
        .tabItem { Label("Arbiter", systemImage: "fanblades") }
      AboutSettingsView()
        .tabItem { Label("About", systemImage: "info.circle") }
    }
    .frame(width: 520, height: 460)
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
  @StateObject private var smcdStatus = SMCDStatus()

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
        helperRow
      } header: {
        Text("Privileged Helper")
      } footer: {
        Text("Reads and writes SMC keys as root. Required for fan control.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section {
        smcdRow
      } header: {
        Text("Fan Arbiter (smcd)")
      } footer: {
        Text(
          "User space arbiter. Mediates fan control between FanCurve and other apps such as lmd by priority. Install from the macos-smc-fan repository with `make smcd-install`."
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
    }
    .formStyle(.grouped)
    .padding()
    .onAppear {
      installState.startMonitoring(xpcClient: xpcClient)
      smcdStatus.startMonitoring(intervalSeconds: 2.0)
    }
    .onDisappear {
      installState.stopMonitoring()
      smcdStatus.stopMonitoring()
    }
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

  private var smcdRow: some View {
    HStack {
      statusDot(ok: smcdStatus.reachable)
      VStack(alignment: .leading, spacing: 2) {
        Text("Fan Arbiter")
          .font(.body)
        Text(smcdSubtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer()
      Text(smcdStatus.reachable ? "Running" : "Unreachable")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var smcdSubtitle: String {
    if smcdStatus.reachable {
      let count = smcdStatus.rows.count
      if count == 0 { return "io.goodkind.smcd. No fans currently claimed." }
      return "io.goodkind.smcd. \(count) fan\(count == 1 ? "" : "s") claimed."
    }
    if let err = smcdStatus.lastError, !err.isEmpty {
      return "io.goodkind.smcd unreachable. \(err)"
    }
    return "io.goodkind.smcd not reachable."
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
        Button("Uninstall") { installState.unregisterAgent() }
          .controlSize(.small)
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
    .padding()
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

/// Live view of smcd arbitration. Shows which client currently owns each
/// fan, at what priority, and how long ago they last wrote. Useful when
/// two fan writers (FanCurve and lmd, for example) are installed and
/// you want to see who is driving RPM right now.
struct ArbiterSettingsView: View {
  @StateObject private var smcdStatus = SMCDStatus()

  var body: some View {
    ScrollView {
      Form {
        Section {
          HStack(spacing: 8) {
            Circle()
              .fill(smcdStatus.reachable ? Color(nsColor: .systemGreen) : Color(nsColor: .systemGray))
              .frame(width: 8, height: 8)
            Text(smcdStatus.reachable ? "Connected to smcd" : "Cannot reach smcd")
              .font(.body)
            Spacer()
            if !smcdStatus.reachable, let err = smcdStatus.lastError {
              Text(err)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
          }
        } header: {
          Text("Status")
        } footer: {
          Text(
            "The arbiter coordinates fan writes between FanCurve and other apps. Install from the macos-smc-fan repository with `make smcd-install` if it is not running."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Section {
          if smcdStatus.rows.isEmpty {
            Text(smcdStatus.reachable ? "No fans currently claimed." : "Waiting for smcd.")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            ForEach(smcdStatus.rows) { row in
              arbiterRow(row)
            }
          }
        } header: {
          Text("Current Owners")
        } footer: {
          Text(
            "Priority preempts a running owner while it is active. Ownership lapses after roughly 10 seconds with no further writes, at which point any client may claim the fan."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .padding()
    }
    .onAppear { smcdStatus.startMonitoring(intervalSeconds: 1.0) }
    .onDisappear { smcdStatus.stopMonitoring() }
  }

  @ViewBuilder
  private func arbiterRow(_ row: ArbiterRow) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Fan \(row.fanIndex)")
          .font(.body)
        Text("owned by \(row.clientName)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text("priority \(row.priority)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        Text(formatAge(row.ageSeconds))
          .font(.caption.monospacedDigit())
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
}

/// Shared About pane. Used both as the Settings > About tab and as the
/// standalone About window that replaces macOS's default panel. Keeps
/// version, update check, author, and build hashes in one place.
struct AboutContentView: View {
  @AppStorage("autoCheckUpdates") private var autoCheck: Bool = true

  @StateObject private var checker = UpdateChecker()

  var body: some View {
    Form {
      Section {
        Toggle("Automatically check on launch", isOn: $autoCheck)

        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Label(statusLabel, systemImage: statusIcon)
              .foregroundColor(statusColor)
              .symbolRenderingMode(.hierarchical)
            if let err = checker.error {
              Text(err)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }

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
    .padding()
    .task {
      if autoCheck { await checker.check() }
    }
  }

  private var statusLabel: String {
    if checker.isChecking { return "Checking..." }
    if checker.error != nil { return "Couldn't check for updates" }
    if checker.isUpdateAvailable, let tag = checker.latestTag {
      return "Update available: \(tag)"
    }
    if checker.latestTag != nil { return "You are up to date" }
    return "Not checked yet"
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

/// Advanced risk-gated settings. Overdrive and Underdrive push beyond the
/// firmware reported safe range. Load Floor raises fans preemptively
/// under CPU load. All three share the "power user" framing.
struct AdvancedSettingsView: View {
  private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

  @AppStorage(SharedConfigKeys.overdriveEnabled, store: suite)
  private var overdrive: Bool = false

  @AppStorage(SharedConfigKeys.underdriveEnabled, store: suite)
  private var underdrive: Bool = false

  @AppStorage(SharedConfigKeys.loadFloorEnabled, store: suite)
  private var loadFloorEnabled: Bool = false

  @AppStorage(SharedConfigKeys.loadFloorThreshold, store: suite)
  private var loadFloorThreshold: Double = 70

  @AppStorage(SharedConfigKeys.gpuLoadFloorThreshold, store: suite)
  private var gpuLoadFloorThreshold: Double = 70

  @AppStorage(SharedConfigKeys.loadFloorPercent, store: suite)
  private var loadFloorPercent: Double = 60

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

        Section {
          Toggle("Raise fans under load", isOn: $loadFloorEnabled)

          if loadFloorEnabled {
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text("Activate when CPU load exceeds")
                Spacer()
                Text("\(Int(loadFloorThreshold))%")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
              Slider(value: $loadFloorThreshold, in: 20...95, step: 5)
            }

            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text("Activate when GPU load exceeds")
                Spacer()
                Text("\(Int(gpuLoadFloorThreshold))%")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
              Slider(value: $gpuLoadFloorThreshold, in: 20...95, step: 5)
            }

            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text("Minimum fan speed while active")
                Spacer()
                Text("\(Int(loadFloorPercent))%")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
              Slider(value: $loadFloorPercent, in: 10...100, step: 5)
            }
          }
        } header: {
          Text("Load Floor")
        } footer: {
          Text(
            "Raises fan speed preemptively when CPU or GPU load stays above its threshold. Never lowers fans below the curve. Uses a short smoothing window to ignore brief spikes."
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
}

/// Computes SHA256 short fingerprints of the main app and embedded agent
/// binaries. Cached in static properties so the About tab does not
/// re-hash on every render.
enum BuildHashes {
  static let appHash: String = shortHash(of: Bundle.main.executableURL)
  static let agentHash: String = shortHash(
    of: Bundle.main.bundleURL
      .appendingPathComponent("Contents/MacOS/\(generatedAgentBundleID)"))

  private static func shortHash(of url: URL?) -> String {
    guard let url, let data = try? Data(contentsOf: url) else { return "n/a" }
    let digest = SHA256.hash(data: data)
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return String(hex.prefix(12))
  }
}
