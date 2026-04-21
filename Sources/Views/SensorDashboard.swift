//
//  SensorDashboard.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import SwiftUI

struct SensorDashboard: View {
  @ObservedObject var sensorState: SensorState
  @ObservedObject var curveModel: FanCurveModel
  @ObservedObject var installState: InstallationState
  @ObservedObject var usage: SystemUsage

  @AppStorage("temperatureUnit") private var unitRaw: String = "celsius"

  private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

  @AppStorage(SharedConfigKeys.overdriveEnabled, store: suite)
  private var overdrive: Bool = false

  @AppStorage(SharedConfigKeys.underdriveEnabled, store: suite)
  private var underdrive: Bool = false

  @AppStorage(SharedConfigKeys.boostEnabled, store: suite)
  private var boost: Bool = false

  @AppStorage(SharedConfigKeys.loadFloorEnabled, store: suite)
  private var loadFloorEnabled: Bool = false

  @AppStorage(SharedConfigKeys.loadFloorThreshold, store: suite)
  private var loadFloorThreshold: Double = 70

  @AppStorage(SharedConfigKeys.gpuLoadFloorThreshold, store: suite)
  private var gpuLoadFloorThreshold: Double = 70

  @AppStorage(SharedConfigKeys.loadFloorPercent, store: suite)
  private var loadFloorPercent: Double = 60


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
          let displayed = Int(unit.convert(fromCelsius: sensorState.governingTemperature))
          Text("\(displayed)")
            .font(.system(.largeTitle, design: .rounded).weight(.regular))
            .foregroundStyle(.primary)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.6), value: displayed)
          Text(unit.symbol)
            .font(.title3)
            .foregroundStyle(.secondary)
        }
      }

      // Live system usage. Each bar gets an inline Load Floor caption
      // when the feature is enabled, anchoring the rule to the metric
      // it actually watches.
      VStack(spacing: 10) {
        let showThresholds = loadFloorEnabled && curveModel.isActive
        VStack(spacing: 4) {
          usageRow(
            label: "CPU", icon: "cpu",
            value: usage.cpuPercent, tint: Color.accentColor,
            threshold: showThresholds ? $loadFloorThreshold : nil)
          if showThresholds {
            loadFloorCaption(
              load: usage.cpuPercent,
              threshold: loadFloorThreshold,
              metric: "CPU")
            .transition(.asymmetric(
              insertion: .opacity.combined(with: .move(edge: .top)),
              removal: .opacity))
          }
        }
        VStack(spacing: 4) {
          usageRow(
            label: "GPU", icon: "memorychip",
            value: usage.gpuPercent, tint: Color.accentColor.opacity(0.55),
            threshold: showThresholds ? $gpuLoadFloorThreshold : nil)
          if showThresholds {
            loadFloorCaption(
              load: usage.gpuPercent,
              threshold: gpuLoadFloorThreshold,
              metric: "GPU")
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
        ForEach(sensorState.fans) { fan in
          fanRow(fan)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .fancurveGlass(
              in: RoundedRectangle(cornerRadius: 8),
              fallbackFill: Color.secondary.opacity(0.06))
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
    .animation(.easeInOut(duration: 0.22), value: curveModel.isActive)
    .animation(.easeInOut(duration: 0.22), value: loadFloorEnabled)
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
      // Liquid Glass button. Off state uses a tinted orange glass so
      // the capsule edge is visible against the dark sidebar. On state
      // fills the capsule with solid orange for a clear state change.
      // Both paths keep text at full contrast against their backgrounds.
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
      .glassEffect(.regular.tint(orange.opacity(0.25)), in: Capsule())
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

  /// Returns true when the fan is actively spinning up or down toward a
  /// new target. A fan at or above its firmware reported max is at its
  /// physical limit, even if the agent commanded a higher target via
  /// Overdrive, so we don't show the ramp indicator in that case.
  private func isRamping(_ fan: FanReading) -> Bool {
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
    if installState.helperReachable, installState.agentEnabled, installState.agentLive {
      return .green
    }
    if installState.helperReachable, installState.agentEnabled, !installState.agentLive {
      return .orange
    }
    if installState.agentEnabled, !installState.helperReachable {
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

  /// Inline caption under a usage bar showing the load floor rule for
  /// that specific metric in plain language. Renders as a Liquid Glass
  /// capsule on macOS 26 and a soft tinted pill on older macOS.
  @ViewBuilder
  private func loadFloorCaption(load: Double, threshold: Double, metric: String) -> some View {
    let active = load >= threshold
    let color = Color(nsColor: .systemTeal)
    let text: String = active
      ? "Minimum \(Int(loadFloorPercent))% fans"
      : "Minimum \(Int(loadFloorPercent))% fans when \(metric) over \(Int(threshold))%"

    HStack(alignment: .top, spacing: 6) {
      Image(systemName: active ? "arrow.up.forward.circle.fill" : "arrow.up.forward.circle")
        .font(.system(size: 11))
      Text(text)
        .font(.caption)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .foregroundStyle(active ? color : .secondary)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .modifier(LoadFloorGlassModifier(color: color, active: active))
    .help(
      "When \(metric) load stays above \(Int(threshold))%, the curve is raised so fans run at least \(Int(loadFloorPercent))%."
    )
  }


  // MARK: - Rows

  @ViewBuilder
  private func usageRow(
    label: String,
    icon: String,
    value: Double,
    tint: Color,
    threshold: Binding<Double>? = nil
  ) -> some View {
    let floorActive = threshold.map { value >= $0.wrappedValue } ?? false
    let floorColor = Color(nsColor: .systemTeal)

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
          .animation(.easeInOut(duration: 0.6), value: Int(value.rounded()))
      }
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 2)
            .fill(Color.secondary.opacity(0.15))
          RoundedRectangle(cornerRadius: 2)
            .fill(floorActive ? floorColor : tint)
            .frame(width: geo.size.width * CGFloat(value / 100))
            .animation(.easeInOut(duration: 0.4), value: value)
          if let threshold {
            thresholdThumb(threshold: threshold, width: geo.size.width, barHeight: geo.size.height)
          }
        }
      }
      .frame(height: 4)
    }
  }

  /// Draggable teal tick marking the load-floor threshold. Wider
  /// invisible hit area makes it easy to grab on a 4pt bar. Snaps to
  /// integer percents so the value reads cleanly in the caption.
  @ViewBuilder
  private func thresholdThumb(threshold: Binding<Double>, width: CGFloat, barHeight: CGFloat)
    -> some View {
    let floorColor = Color(nsColor: .systemTeal)
    let x = width * CGFloat(threshold.wrappedValue / 100)

    ZStack {
      Rectangle()
        .fill(Color.clear)
        .contentShape(Rectangle())
        .frame(width: 18, height: 22)
      Rectangle()
        .fill(floorColor)
        .frame(width: 2.5, height: 14)
    }
    .position(x: x, y: barHeight / 2 + 3)
    .help("Drag to set the load-floor threshold. Currently \(Int(threshold.wrappedValue))%.")
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          guard width > 0 else { return }
          let pct = Double(value.location.x / width) * 100
          threshold.wrappedValue = max(1, min(99, pct.rounded()))
        }
    )
  }

  private func fanRow(_ fan: FanReading) -> some View {
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
            .animation(.easeInOut(duration: 0.6), value: Int(fan.actualRPM))
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
    let icon = Image(systemName: "fan.fill")
      .font(.caption)
      .foregroundColor(spinning ? Color.accentColor : .secondary)
    if #available(macOS 15.0, *) {
      icon.symbolEffect(.rotate, isActive: spinning)
    } else {
      icon
    }
  }

  /// Liquid Glass capsule for the load floor caption. On macOS 26 it
  /// uses the real glass effect. Below that it falls back to a soft
  /// tinted pill so the visual shape stays consistent.
  private struct LoadFloorGlassModifier: ViewModifier {
    let color: Color
    let active: Bool

    func body(content: Content) -> some View {
      if #available(macOS 26.0, *) {
        content
          .background(Capsule().fill(color.opacity(active ? 0.18 : 0.06)))
          .glassEffect(in: Capsule())
          .overlay(
            Capsule().stroke(color.opacity(active ? 0.7 : 0.4), lineWidth: 2.5)
          )
      } else {
        content
          .background(Capsule().fill(color.opacity(active ? 0.18 : 0.08)))
          .overlay(
            Capsule().stroke(color.opacity(active ? 0.7 : 0.4), lineWidth: 2.5)
          )
      }
    }
  }

  private var tempColor: Color {
    let t = sensorState.governingTemperature
    if t < 55 { return Color(nsColor: .systemGreen) }
    if t < 75 { return Color(nsColor: .systemYellow) }
    if t < 90 { return Color(nsColor: .systemOrange) }
    return Color(nsColor: .systemRed)
  }
}
