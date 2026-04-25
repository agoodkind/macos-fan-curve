//
//  SensorDashboard.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import SwiftUI

struct SensorDashboard: View {
  @ObservedObject var runtime: AgentSnapshotState
  @ObservedObject var curveModel: FanCurveModel
  @ObservedObject var installState: InstallationState

  @AppStorage("temperatureUnit") private var unitRaw: String = "celsius"

  private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

  @AppStorage(SharedConfigKeys.boostEnabled, store: suite)
  private var boost: Bool = false

  @AppStorage(SharedConfigKeys.cpuLoadAssistEnabled, store: suite)
  private var cpuLoadAssistEnabled: Bool = false

  @AppStorage(SharedConfigKeys.gpuLoadAssistEnabled, store: suite)
  private var gpuLoadAssistEnabled: Bool = false


  private var unit: TemperatureUnit {
    TemperatureUnit(rawValue: unitRaw) ?? .celsius
  }

  var body: some View {
    GeometryReader { geo in
      ScrollView {
        sidebarContent
          .frame(minHeight: geo.size.height)
      }
      .scrollIndicators(.hidden)
    }
    .fancurveGlass(
      in: RoundedRectangle(cornerRadius: 0),
      fallbackFill: Color(nsColor: .windowBackgroundColor))
    .onAppear {
      LoadAssistStore.migrateLegacyIfNeeded(defaults: Self.suite)
    }
  }

  private var sidebarContent: some View {
    VStack(alignment: .leading, spacing: 24) {
      // Hero temperature. HIG favors restrained typography, so we use
      // largeTitle at label color rather than a colorful glowing number.
      // A small tinted dot beside the caption carries the thermal state.
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Image(systemName: "thermometer.medium")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text("CPU Temperature")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Circle()
            .fill(tempColor)
            .frame(width: 6, height: 6)
        }

        HStack(alignment: .firstTextBaseline, spacing: 2) {
          let displayed = Int(unit.convert(fromCelsius: runtime.governingTemperature))
          Text("\(displayed)")
            .font(.system(.largeTitle, design: .rounded).weight(.regular))
            .foregroundStyle(.primary)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.38), value: displayed)
          Text(unit.symbol)
            .font(.title3)
            .foregroundStyle(.secondary)
        }
      }

      let assistStates = activeAssistStates

      // Live system usage with compact assist indicators when a CPU/GPU
      // load assist is actively raising the current floor.
      VStack(spacing: 10) {
        VStack(spacing: 4) {
          usageRow(
            label: "CPU", icon: "cpu",
            value: runtime.cpuLoadPercent, tint: Color.accentColor)
          if let assist = assistStates.first(where: { $0.kind == .cpu }) {
            loadAssistCaption(assist)
            .transition(.asymmetric(
              insertion: .opacity.combined(with: .move(edge: .top)),
              removal: .opacity))
          }
        }
        VStack(spacing: 4) {
          usageRow(
            label: "GPU", icon: "memorychip",
            value: runtime.gpuLoadPercent, tint: Color.accentColor.opacity(0.55))
          if let assist = assistStates.first(where: { $0.kind == .gpu }) {
            loadAssistCaption(assist)
            .transition(.asymmetric(
              insertion: .opacity.combined(with: .move(edge: .top)),
              removal: .opacity))
          }
        }
      }

      // Fans. Each row sits in its own subtle card so they separate
      // visually inside the sidebar. A thin outline keeps the card
      // readable even when the window is focused and glass is less
      // pronounced from the system chrome.
      VStack(spacing: 10) {
        ForEach(runtime.fans) { fan in
          fanRow(fan)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
              RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06)))
            .overlay(
              RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
      }

      Divider().opacity(0.15)

      // Controls. While Boost is on, the curve is paused and the Fan
      // Control toggle locks so the user cannot accidentally turn fans
      // back to firmware auto while they are relying on boost cooling.
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Fan Control")
            .font(.body)
          Text(fanControlStateLabel)
            .font(.caption)
            .foregroundColor(fanControlStateColor)
          if curveModel.isActive && !boost {
            Text(controllerStateLabel)
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
        Spacer()
        Toggle("", isOn: $curveModel.isActive)
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.regular)
          .tint(Color.accentColor)
          .disabled(boost)
          .help(boost ? "Turn Boost off first to change this." : "")
      }

      // Boost pins fans to 100% while on. Hidden entirely when Fan
      // Control is off because boost cannot run without the agent
      // applying a target, so showing a dimmed button there is noise.
      if curveModel.isActive {
        boostButton
          .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity))
      }

      Spacer()

      // Helper health and any active mode warnings sit at the bottom of
      // the sidebar so they don't compete with the primary controls.
      statusBlock
    }
    .padding(.horizontal, 20)
    .padding(.top, 24)
    .padding(.bottom, 20)
  }

  /// Boost as a plain Button so the text stays high contrast in both
  /// states. Prominent style when active, plain bordered when inactive.
  /// Label flips between Boost Fans and Stop Boost so the action verb
  /// always matches the next state.
  @ViewBuilder
  private var boostButton: some View {
    let label = Label(
      boost ? "Stop Boost" : "Boost Fans",
      systemImage: "bolt.fill")
    if #available(macOS 26.0, *) {
      let orange = Color(nsColor: .systemOrange)
      Button { boost.toggle() } label: {
        ZStack {
          Text(boost ? "Stop Boost" : "Boost Fans")
            .foregroundStyle(boost ? Color.white : Color.primary)
          HStack {
            Image(systemName: "bolt.fill")
              .foregroundStyle(boost ? Color.white : orange)
            Spacer()
          }
          .padding(.leading, 14)
        }
        .font(.callout.weight(.medium))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
      }
      .buttonStyle(.plain)
      .background {
        Capsule()
          .fill(boost ? orange : orange.opacity(0.12))
      }
      .overlay(
        Capsule()
          .stroke(orange.opacity(boost ? 0 : 0.45), lineWidth: 0.8)
      )
      .help(boostHelp)
    } else if boost {
      Button { boost.toggle() } label: {
        label.frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(Color(nsColor: .systemOrange))
      .controlSize(.regular)
      .help(boostHelp)
    } else {
      Button { boost.toggle() } label: {
        label.frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .controlSize(.regular)
      .help(boostHelp)
    }
  }

  /// Text shown under the Fan Control label. Boost takes precedence so
  /// the user sees why the curve is paused.
  private var fanControlStateLabel: String {
    if boost { return "Boost active" }
    return curveModel.isActive ? "Curve active" : "Off"
  }

  private var fanControlStateColor: Color {
    if boost { return Color(nsColor: .systemOrange) }
    return curveModel.isActive ? Color.accentColor : .secondary
  }

  private var controllerStateLabel: String {
    let committed = Int((runtime.committedPercent * 100).rounded())
    switch runtime.controllerMode {
    case .holding:
      if runtime.holdRemainingSeconds > 0 {
        return "Targeting \(committed)%"
      }
      return "Targeting \(committed)%"
    case .rampingUp:
      return "Stepping up toward \(committed)%"
    case .rampingDown:
      return "Cooling down toward \(committed)%"
    case .emergency:
      return "Emergency ramp"
    }
  }

  /// Returns true when the fan is actively spinning up or down toward a
  /// new target. A fan at or above its firmware reported max is at its
  /// physical limit, even if the agent commanded a higher target via
  /// Overdrive, so we don't show the ramp indicator in that case.
  private func isRamping(_ fan: AgentFanSnapshot) -> Bool {
    let target = fan.targetRPM
    guard target > 0 else { return false }
    // Fan has reached its mechanical ceiling. It cannot climb further.
    if fan.actualRPM >= fan.maxRPM - 50 { return false }
    // 5% tolerance with a 250 RPM minimum handles both slow-spin and
    // high-RPM targets proportionally.
    let tolerance = max(250, target * 0.05)
    return abs(fan.actualRPM - target) > tolerance
  }

  private var boostHelp: String {
    "Pins all fans to 100% (or Overdrive target) while enabled. Useful for brief emergency cooling."
  }

  // MARK: - Status

  private enum SystemStatus { case green, orange, red }

  private var systemStatus: SystemStatus {
    let helperReachable = runtime.isFresh ? runtime.helperReachable : installState.helperReachable
    if helperReachable, installState.agentEnabled, installState.agentLive {
      return .green
    }
    if helperReachable, installState.agentEnabled, !installState.agentLive {
      return .orange
    }
    if installState.agentEnabled, !helperReachable {
      return .orange
    }
    return .red
  }

  private var statusLabel: String {
    switch systemStatus {
    case .green: return "All systems go"
    case .orange:
      if installState.agentEnabled, !installState.agentLive {
        return "Agent not responding"
      }
      return "Helper offline"
    case .red: return "Not connected"
    }
  }

  private var statusColor: Color {
    switch systemStatus {
    case .green: return Color(nsColor: .systemGreen)
    case .orange: return Color(nsColor: .systemOrange)
    case .red: return Color(nsColor: .systemRed)
    }
  }

  @ViewBuilder
  private var statusBlock: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Circle()
          .fill(statusColor)
          .frame(width: 8, height: 8)
          .shadow(color: statusColor.opacity(0.6), radius: 3)
        Text(statusLabel)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(1)
        Spacer()
      }
      if !installState.agentLastError.isEmpty {
        Text(installState.agentLastError)
          .font(.caption2)
          .foregroundColor(.secondary)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .help(installState.agentLastError)
      }
    }
  }

  private struct ActiveAssistState: Identifiable {
    let kind: LoadAssistKind
    let loadPercent: Double
    let floorPercent: Double

    var id: String { kind.rawValue }
  }

  private var activeAssistStates: [ActiveAssistState] {
    guard curveModel.isActive, !boost else { return [] }
    let curveReferenceTemp = runtime.rawPressureTemperature ?? runtime.governingTemperature
    let basePercent = curveModel.evaluate(at: curveReferenceTemp)
    var candidates: [ActiveAssistState] = []
    let floorPercent = runtime.assistFloorPercent ?? 0
    for kind in LoadAssistKind.allCases {
      let enabled = kind == .cpu ? cpuLoadAssistEnabled : gpuLoadAssistEnabled
      guard enabled else { continue }
      let load = kind == .cpu ? runtime.cpuLoadPercent : runtime.gpuLoadPercent
      guard runtime.activeAssistKinds.contains(kind), floorPercent > basePercent + 0.005 else { continue }
      candidates.append(ActiveAssistState(kind: kind, loadPercent: load, floorPercent: floorPercent))
    }
    guard let maxFloor = candidates.map(\.floorPercent).max() else { return [] }
    return candidates.filter { abs($0.floorPercent - maxFloor) < 0.001 }
  }

  /// Inline caption under a usage bar showing when a load assist is
  /// actively raising the effective floor right now.
  @ViewBuilder
  private func loadAssistCaption(_ assist: ActiveAssistState) -> some View {
    let color = Color(nsColor: .systemTeal)
    let floor = Int((assist.floorPercent * 100).rounded())
    let load = Int(assist.loadPercent.rounded())
    let text = "\(assist.kind.shortTitle) assist holding minimum \(floor)% at \(load)% load"

    HStack(alignment: .top, spacing: 6) {
      Image(systemName: "arrow.up.forward.circle.fill")
        .font(.system(size: 11))
      Text(text)
        .font(.caption)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .foregroundStyle(color)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .modifier(LoadFloorGlassModifier(color: color, active: true))
    .help(
      "\(assist.kind.title) is active and is currently raising the effective minimum fan floor to \(floor)%."
    )
  }


  // MARK: - Rows

  @ViewBuilder
  private func usageRow(
    label: String,
    icon: String,
    value: Double,
    tint: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Image(systemName: icon)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(label)
          .font(.callout)
          .foregroundColor(.secondary)
        Spacer()
        Text("\(Int(value.rounded()))%")
          .font(.system(.callout, design: .rounded).weight(.medium))
          .monospacedDigit()
          .contentTransition(.numericText())
          .animation(.easeOut(duration: 0.32), value: value)
      }
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 2)
            .fill(Color.secondary.opacity(0.15))
          RoundedRectangle(cornerRadius: 2)
            .fill(tint)
            .frame(width: geo.size.width * CGFloat(value / 100))
            .animation(.easeOut(duration: 0.34), value: value)
        }
      }
      .frame(height: 4)
    }
  }

  private func fanRow(_ fan: AgentFanSnapshot) -> some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          fanIcon(spinning: fan.actualRPM > 0)
          Text("Fan \(fan.id)")
            .font(.callout)
            .foregroundColor(.secondary)
          if fan.manualMode {
            Text("Manual")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text("\(Int(fan.actualRPM))")
            .font(.system(.title3, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.4), value: fan.actualRPM)
          Text("RPM")
            .font(.caption)
            .foregroundColor(.secondary)
          if isRamping(fan) {
            ProgressView()
              .controlSize(.mini)
              .scaleEffect(0.7)
              .help(
                "Ramping to \(Int(fan.targetRPM)) RPM. Spinner stops when the fan settles within range."
              )
          }
        }
      }
      Spacer()
    }
  }

  @ViewBuilder
  private func fanIcon(spinning: Bool) -> some View {
    Image(systemName: "fan.fill")
      .font(.caption)
      .foregroundColor(spinning ? Color.accentColor : .secondary)
  }

  /// Liquid Glass capsule for the load floor caption. On macOS 26 it
  /// uses the real glass effect. Below that it falls back to a soft
  /// tinted pill so the visual shape stays consistent.
  private struct LoadFloorGlassModifier: ViewModifier {
    let color: Color
    let active: Bool

    func body(content: Content) -> some View {
      content
        .background(Capsule().fill(color.opacity(active ? 0.18 : 0.08)))
        .overlay(
          Capsule().stroke(color.opacity(active ? 0.7 : 0.4), lineWidth: 1.0)
        )
    }
  }

  private var tempColor: Color {
    let t = runtime.governingTemperature
    if t < 55 { return Color(nsColor: .systemGreen) }
    if t < 75 { return Color(nsColor: .systemYellow) }
    if t < 90 { return Color(nsColor: .systemOrange) }
    return Color(nsColor: .systemRed)
  }
}
