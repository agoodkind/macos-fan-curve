//
//  FanCurveEditor.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import SwiftUI

struct FanCurveEditor: View {
  @ObservedObject var model: FanCurveModel
  @ObservedObject var runtime: AgentSnapshotState
  @State private var hoveredIndex: Int?
  @State private var draggedIndex: Int?
  @State private var mouseLocation: CGPoint?
  @State private var targetCommittedTemperature: Double = 0
  @State private var targetCommittedPercent: Double = 0
  @State private var targetRawTemperature: Double = 0
  @State private var targetRawPercent: Double = 0
  @State private var displayedCommittedTemperature: Double = 0
  @State private var displayedCommittedPercent: Double = 0
  @State private var displayedRawTemperature: Double = 0
  @State private var displayedRawPercent: Double = 0
  @State private var markerSmoothingTask: Task<Void, Never>?
  @State private var lastMarkerUpdateTime: ContinuousClock.Instant?

  private let controlPointHitRadius: CGFloat = 14

  @AppStorage("temperatureUnit") private var unitRaw: String = "celsius"

  private var unit: TemperatureUnit {
    TemperatureUnit(rawValue: unitRaw) ?? .celsius
  }

  private func displayTemp(_ celsius: Double) -> Int {
    Int(unit.convert(fromCelsius: celsius).rounded())
  }

  /// Crossfade driver between active and inactive curve rendering. 1 is
  /// fully active (blue solid user curve, no ghost). 0 is fully inactive
  /// (gray dashed user curve, accent-colored Apple ghost). SwiftUI
  /// animates this on toggle so Canvas redraws with interpolated opacity
  /// each frame, giving a smooth transition.
  @State private var activePhase: Double = 1.0

  private let topPad: CGFloat = 56
  private let bottomPad: CGFloat = 44
  private let leftPad: CGFloat = 72
  private let rightPad: CGFloat = 24
  private let minimumPointSpacing: Double = 2

  private let tempRange: ClosedRange<Double> = 20...100
  private let curveColor = Color.accentColor

  @AppStorage(SharedConfigKeys.overdriveEnabled, store: Self.suite)
  private var overdriveEnabled: Bool = false

  @AppStorage(SharedConfigKeys.underdriveEnabled, store: Self.suite)
  private var underdriveEnabled: Bool = false

  @AppStorage(SharedConfigKeys.boostEnabled, store: Self.suite)
  private var boostEnabled: Bool = false

  private static let suite = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard

  /// Visual scale for the Y axis follows the effective fan control range.
  /// Overdrive extends the top to the configured target. Underdrive drops
  /// the bottom to zero. When neither is on the axis uses the firmware
  /// reported minimum and maximum.
  private var rpmRange: (min: Float, max: Float) {
    guard let fan = runtime.fans.first else { return (0, 8000) }
    let minR: Float = underdriveEnabled ? 0 : fan.minRPM
    let maxR: Float = overdriveEnabled ? max(fan.maxRPM, overdriveTargetRPM) : fan.maxRPM
    return (minR, maxR)
  }

  private let markerSmoothingInterval: UInt64 = 16_000_000
  private let committedMarkerTemperatureHalfLife: Double = 0.9
  private let committedMarkerPercentHalfLife: Double = 0.78
  private let rawMarkerTemperatureHalfLife: Double = 0.38
  private let rawMarkerPercentHalfLife: Double = 0.3

  var body: some View {
    GeometryReader { geo in
      let size = geo.size

      ZStack {
        Canvas { context, canvasSize in
          drawGrid(context: context, size: canvasSize)
          drawCurve(context: context, size: canvasSize)
          drawHoverLine(context: context, size: canvasSize)
          drawAxisTitles(context: context, size: canvasSize)
        }
        .contentShape(Rectangle())
        // Point dragging is the only editing mode in this pass.
        // Disabling segment dragging keeps the monotonic rules
        // predictable while we tighten the core curve behavior.

        controlPointsOverlay(size: size)
        // Current position and Now label render last so they sit on top
        // of the curve line and all control points.
        currentPositionOverlay(size: size)
        hoverTooltipOverlay(size: size)
        boostOverlay(size: size)
        modeBadgesOverlay
        appleAutoLabelOverlay(size: size)
      }
      .onContinuousHover { phase in
        switch phase {
        case .active(let location):
          mouseLocation = location
          if draggedIndex == nil {
            hoveredIndex = hoveredControlPointIndex(at: location, in: size)
          }
        case .ended:
          mouseLocation = nil
          if draggedIndex == nil {
            hoveredIndex = nil
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .fancurveGlassCard(cornerRadius: 12)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .onAppear { activePhase = model.isActive ? 1.0 : 0.0 }
    .onChange(of: model.isActive) { newActive in
      withAnimation(.easeInOut(duration: 0.35)) {
        activePhase = newActive ? 1.0 : 0.0
      }
    }
    .onAppear {
      refreshRuntimeMarkerTargets()
      displayedCommittedTemperature = targetCommittedTemperature
      displayedCommittedPercent = targetCommittedPercent
      displayedRawTemperature = targetRawTemperature
      displayedRawPercent = targetRawPercent
      startMarkerSmoothing()
    }
    .onChange(of: runtime.committedTemperature) { newTemperature in
      refreshRuntimeMarkerTargets()
    }
    .onChange(of: runtime.committedPercent) { newPercent in
      refreshRuntimeMarkerTargets()
    }
    .onChange(of: runtime.rawPressureTemperature) { newTemperature in
      refreshRuntimeMarkerTargets()
    }
    .onChange(of: runtime.rawBaselinePercent) { newPercent in
      refreshRuntimeMarkerTargets()
    }
    .onChange(of: runtime.activeAssistKinds) { _ in
      refreshRuntimeMarkerTargets()
    }
    .onChange(of: boostEnabled) { _ in
      refreshRuntimeMarkerTargets()
    }
    .onDisappear {
      markerSmoothingTask?.cancel()
      markerSmoothingTask = nil
      lastMarkerUpdateTime = nil
    }
  }

  // MARK: - Header

  /// Compact caption above the chart. The window title already says
  /// FanCurve, so a second H1 here would be redundant. A single caption
  /// line carries the operational state and keeps the chart as the hero.
  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      if model.isActive {
        Circle()
          .fill(Color(nsColor: .systemGreen))
          .frame(width: 6, height: 6)
        Text("Fans are following this curve")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Circle()
          .fill(Color.secondary.opacity(0.5))
          .frame(width: 6, height: 6)
        Text("Preview only. Turn on Fan Control to apply.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
  }

  // MARK: - Current Position Overlay

  @ViewBuilder
  private func currentPositionOverlay(size: CGSize) -> some View {
    Group {
      let committedTemp = displayedCommittedTemperature
      let committedPercent = displayedCommittedPercent
      let rawTemp = displayedRawTemperature
      let rawPercent = displayedRawPercent
      if committedTemp > 0 {
        let committedPos = dataToPixel(temp: committedTemp, percent: committedPercent, in: size)
        let rawPos = dataToPixel(temp: rawTemp, percent: rawPercent, in: size)
        let plotLeft = leftPad
        let zeroY = dataToPixel(temp: 20, percent: 0, in: size).y
        let dashLine = StrokeStyle(lineWidth: 1, dash: [4, 4])

        // Vertical dashed line from the actual dot down to the X axis.
        // Uses a Shape with explicit height so .position() animates smoothly
        // alongside the orange dot when the temperature changes.
        DashedLine(axis: .vertical)
          .stroke(Color(nsColor: .systemOrange).opacity(0.25), style: dashLine)
          .frame(width: 1, height: max(0, zeroY - committedPos.y))
          .position(x: committedPos.x, y: (committedPos.y + zeroY) / 2)

        // Horizontal dashed line from the Y axis to the actual dot.
        // Balances the vertical guide and surfaces the current fan percent.
        DashedLine(axis: .horizontal)
          .stroke(Color(nsColor: .systemOrange).opacity(0.25), style: dashLine)
          .frame(width: max(0, committedPos.x - plotLeft), height: 1)
          .position(x: (plotLeft + committedPos.x) / 2, y: committedPos.y)

        if hypot(rawPos.x - committedPos.x, rawPos.y - committedPos.y) > 6 {
          Path { path in
            path.move(to: committedPos)
            path.addLine(to: rawPos)
          }
          .stroke(Color(nsColor: .systemOrange).opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }

        Circle()
          .stroke(Color(nsColor: .systemOrange).opacity(0.32), lineWidth: 1.25)
          .frame(width: 7, height: 7)
          .position(rawPos)
          .animation(.easeInOut(duration: 0.42), value: rawPos)

        if mouseLocation == nil,
           hypot(rawPos.x - committedPos.x, rawPos.y - committedPos.y) > 22 {
          pressureLabel
            .position(x: rawPos.x, y: rawPos.y + 16)
            .animation(.easeInOut(duration: 0.42), value: rawPos)
        }

        Circle()
          .fill(Color(nsColor: .systemOrange))
          .frame(width: 10, height: 10)
          .shadow(color: Color(nsColor: .systemOrange).opacity(0.5), radius: 6)
          .position(committedPos)
          .animation(.timingCurve(0.18, 0.82, 0.22, 1.0, duration: 0.55), value: committedPos)

        if mouseLocation == nil {
          nowLabel
            .position(x: committedPos.x, y: committedPos.y - 16)
            .animation(.timingCurve(0.18, 0.82, 0.22, 1.0, duration: 0.55), value: committedPos)
        }
      }
    }
    .allowsHitTesting(false)
  }

  private func refreshRuntimeMarkerTargets() {
    if runtime.curveActive {
      targetCommittedPercent = runtime.committedPercent
      targetCommittedTemperature = committedMarkerTemperatureTarget()
      targetRawTemperature = runtime.rawPressureTemperature ?? runtime.governingTemperature
      targetRawPercent = runtime.rawBaselinePercent
    } else {
      let livePercent = liveFanPercent()
      targetCommittedPercent = livePercent
      targetCommittedTemperature = projectedCurveTemperature(
        for: livePercent,
        points: CurvePresets.appleSilent.curvePoints(),
        mode: .catmullRom
      ) ?? runtime.governingTemperature
      targetRawTemperature = runtime.governingTemperature
      targetRawPercent = livePercent
    }
  }

  private func committedMarkerTemperatureTarget() -> Double {
    guard runtime.committedPercent > 0 else {
      return tempRange.lowerBound
    }

    // Keep the primary marker on the authored curve so the chart remains
    // visually truthful. The faint secondary marker carries the live thermal
    // pressure/current-state context.
    if let projectedTemperature = projectedCurveTemperature(
      for: runtime.committedPercent,
      points: model.controlPoints,
      mode: model.interpolationMode
    ) {
      return projectedTemperature
    }

    return runtime.committedTemperature
  }

  private func projectedCurveTemperature(
    for percent: Double,
    points: [CurvePoint],
    mode: InterpolationMode
  ) -> Double? {
    let clampedPercent = max(0, min(1, percent))
    let minCurvePercent = CurveInterpolation.evaluate(at: tempRange.lowerBound, points: points, mode: mode)
    let maxCurvePercent = CurveInterpolation.evaluate(at: tempRange.upperBound, points: points, mode: mode)

    guard clampedPercent >= minCurvePercent - 0.0005,
          clampedPercent <= maxCurvePercent + 0.0005 else {
      return nil
    }

    var lower = tempRange.lowerBound
    var upper = tempRange.upperBound

    for _ in 0..<28 {
      let mid = (lower + upper) / 2
      let value = CurveInterpolation.evaluate(at: mid, points: points, mode: mode)
      if value < clampedPercent {
        lower = mid
      } else {
        upper = mid
      }
    }

    return (lower + upper) / 2
  }

  private func liveFanPercent() -> Double {
    guard let fan = runtime.fans.first else { return 0 }
    let span = max(1, fan.maxRPM - fan.minRPM)
    let normalized = Double((fan.actualRPM - fan.minRPM) / span)
    return max(0, min(1, normalized))
  }

  /// Horizontal line showing the Load Floor minimum. Solid and labeled
  /// "Active" when CPU load is above the threshold and the agent is
  /// actually enforcing the floor. Dashed and muted otherwise so the
  /// user knows it is armed but not currently applied.
  /// Overlay that kicks in when Boost is active. Shades everything below
  /// the 100% line to make it clear the curve is temporarily bypassed.
  @ViewBuilder
  private func boostOverlay(size: CGSize) -> some View {
    if boostEnabled {
      let plotLeft = leftPad
      let plotRight = size.width - rightPad
      let plotTop = topPad
      let topY = dataToPixel(temp: 20, percent: 1.0, in: size).y
      let lineColor = Color(nsColor: .systemOrange)

      // Very subtle wash so the curve and grid stay readable. The
      // horizontal line at 100% and the Boost pill carry the state.
      Rectangle()
        .fill(lineColor.opacity(0.03))
        .frame(width: plotRight - plotLeft, height: size.height - plotTop - bottomPad)
        .position(
          x: (plotLeft + plotRight) / 2,
          y: (plotTop + (size.height - bottomPad)) / 2)
        .allowsHitTesting(false)

      Rectangle()
        .fill(lineColor)
        .frame(width: plotRight - plotLeft, height: 2)
        .position(x: (plotLeft + plotRight) / 2, y: topY)
        .allowsHitTesting(false)

      Group {
        let label = HStack(spacing: 4) {
          Image(systemName: "bolt.fill")
            .font(.caption2)
          Text("Boost: fans at 100%")
            .font(.system(.caption2, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(lineColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)

        if #available(macOS 26.0, *) {
          label
            .glassEffect(in: Capsule())
            .overlay(Capsule().stroke(lineColor.opacity(0.45), lineWidth: 0.5))
        } else {
          label
            .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(Capsule().stroke(lineColor.opacity(0.45), lineWidth: 0.5))
        }
      }
      .position(x: plotRight - 62, y: topY)
      .allowsHitTesting(false)
    }
  }

  /// Orange capsules pinned to the top-right of the plot that surface
  /// Overdrive / Underdrive being on. Placed on the graph so the warning
  /// lives next to the curve it is actually modifying rather than in the
  /// sidebar status area.
  @ViewBuilder
  private var modeBadgesOverlay: some View {
    if overdriveEnabled || underdriveEnabled {
      VStack(alignment: .trailing, spacing: 6) {
        HStack(spacing: 6) {
          Spacer()
          if overdriveEnabled {
            modePill(
              label: "Overdrive on",
              tooltip:
                "Overdrive is on. 100% on the curve pushes fans beyond the firmware reported max, up to \(Int(overdriveTargetRPM)) RPM. Sustained high RPM shortens bearing life and increases noise. Turn off in Settings > Curve > Advanced."
            )
          }
          if underdriveEnabled {
            modePill(
              label: "Underdrive on",
              tooltip:
                "Underdrive is on. 0% on the curve forces fans to 0 RPM in manual mode. Without airflow your machine can overheat, throttle, or shut down under load. Turn off in Settings > Curve > Advanced."
            )
          }
        }
        Spacer()
      }
      .padding(.top, 12)
      .padding(.trailing, 12)
      .transition(.opacity)
      .allowsHitTesting(false)
    }
  }

  @ViewBuilder
  private func modePill(label: String, tooltip: String) -> some View {
    let orange = Color(nsColor: .systemOrange)
    let content = HStack(spacing: 4) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 9))
      Text(label)
        .font(.system(.caption2, design: .rounded).weight(.medium))
        .lineLimit(1)
    }
    .fixedSize()
    .foregroundColor(orange)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)

    if #available(macOS 26.0, *) {
      content
        .background(Capsule().fill(orange.opacity(0.15)))
        .glassEffect(in: Capsule())
        .help(tooltip)
    } else {
      content
        .background(Capsule().fill(orange.opacity(0.15)))
        .help(tooltip)
    }
  }

  // MARK: - Grid and Axes

  private func drawGrid(context: GraphicsContext, size: CGSize) {
    let gridColor = Color.primary.opacity(0.05)
    let labelColor = Color.secondary

    let plotLeft = leftPad
    let plotRight = size.width - rightPad
    let plotTop = topPad
    let plotBottom = size.height - bottomPad

    // Horizontal gridlines and Y axis labels (percent plus RPM)
    for pct in stride(from: 0.0, through: 1.0, by: 0.2) {
      let y = dataToPixel(temp: 20, percent: pct, in: size).y
      var line = Path()
      line.move(to: CGPoint(x: plotLeft, y: y))
      line.addLine(to: CGPoint(x: plotRight, y: y))
      context.stroke(line, with: .color(gridColor), lineWidth: 0.5)

      let pctText = Text("\(Int(pct * 100))%")
        .font(.system(.caption2, design: .rounded))
        .foregroundColor(labelColor)
      context.draw(pctText, at: CGPoint(x: plotLeft - 30, y: y), anchor: .center)

      let rpm = Int(rpmRange.min + Float(pct) * (rpmRange.max - rpmRange.min))
      let rpmText = Text(rpm.formatted())
        .font(.system(size: 9, design: .rounded))
        .foregroundColor(labelColor.opacity(0.6))
      context.draw(rpmText, at: CGPoint(x: plotLeft - 30, y: y + 11), anchor: .center)
    }

    // Vertical gridlines and X axis labels
    for temp in stride(from: 20.0, through: 100.0, by: 10.0) {
      let x = dataToPixel(temp: temp, percent: 0, in: size).x
      var line = Path()
      line.move(to: CGPoint(x: x, y: plotTop))
      line.addLine(to: CGPoint(x: x, y: plotBottom))
      context.stroke(line, with: .color(gridColor), lineWidth: 0.5)

      if Int(temp) % 20 == 0 {
        let text = Text("\(displayTemp(temp))\(unit.symbol)")
          .font(.system(.caption2, design: .rounded))
          .foregroundColor(labelColor)
        context.draw(text, at: CGPoint(x: x, y: plotBottom + 14), anchor: .center)
      }
    }
  }

  private func drawAxisTitles(context: GraphicsContext, size: CGSize) {
    let titleColor = Color.secondary.opacity(0.8)

    let xTitle = Text("Temperature (\(unit.symbol))")
      .font(.system(.caption2, design: .rounded).weight(.medium))
      .foregroundColor(titleColor)
    context.draw(
      xTitle,
      at: CGPoint(x: (leftPad + size.width - rightPad) / 2, y: size.height - 12),
      anchor: .center)

    // Y axis title sits above the top tick. topPad leaves 16pt of space
    // above the 100% tick for this label so the two do not overlap.
    let yTitle = Text("Fan Speed (% / RPM)")
      .font(.system(.caption2, design: .rounded).weight(.medium))
      .foregroundColor(titleColor)
    context.draw(
      yTitle,
      at: CGPoint(x: leftPad - 48, y: topPad - 24),
      anchor: .leading)
  }

  // MARK: - Curve

  private func drawCurve(context: GraphicsContext, size: CGSize) {
    // Ghost always drawn but scaled by (1 - activePhase) so it fades in
    // as fan control turns off.
    drawGhostCurve(context: context, size: size, opacity: 1.0 - activePhase)

    let pathPoints = CurveInterpolation.pathPoints(
      points: model.controlPoints, mode: model.interpolationMode,
      tempRange: tempRange, steps: 300)
    guard !pathPoints.isEmpty else { return }

    let pixelPoints = pathPoints.map { dataToPixel(temp: $0.0, percent: $0.1, in: size) }
    let firstPt = pixelPoints.first!
    let lastPt = pixelPoints.last!
    let zeroY = dataToPixel(temp: 20, percent: 0, in: size).y

    // Line is the smoothed polyline. Fill reuses the line path but
    // closes back to the baseline so the gradient under the curve is
    // bounded by the same smoothed shape.
    let line = smoothedPath(through: pixelPoints)
    var fill = line
    fill.addLine(to: CGPoint(x: lastPt.x, y: zeroY))
    fill.addLine(to: CGPoint(x: firstPt.x, y: zeroY))
    fill.closeSubpath()

    let phase = activePhase
    let inversePhase = 1.0 - activePhase

    if phase > 0.01 {
      context.fill(
        fill,
        with: .linearGradient(
          Gradient(colors: [curveColor.opacity(0.18 * phase), curveColor.opacity(0.0)]),
          startPoint: CGPoint(x: 0, y: topPad),
          endPoint: CGPoint(x: 0, y: size.height - bottomPad)))

      context.stroke(
        line, with: .color(curveColor.opacity(0.15 * phase)),
        style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
      context.stroke(
        line, with: .color(curveColor.opacity(phase)),
        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }

    if inversePhase > 0.01 {
      context.stroke(
        line, with: .color(Color.secondary.opacity(0.3 * inversePhase)),
        style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round, dash: [4, 5]))
    }
  }

  /// Builds a visually-smoothed path through a sampled polyline by
  /// replacing straight segments with quadratic Beziers through the
  /// midpoint of each pair. This rounds micro-corners that appear when
  /// adjacent control points sit close in temperature with a big
  /// percent jump. Evaluation stays authoritative; only rendering is
  /// smoothed.
  private func smoothedPath(through pts: [CGPoint]) -> Path {
    var path = Path()
    guard let first = pts.first else { return path }
    path.move(to: first)
    guard pts.count >= 3 else {
      for p in pts.dropFirst() { path.addLine(to: p) }
      return path
    }
    for i in 1..<(pts.count - 1) {
      let mid = CGPoint(
        x: (pts[i].x + pts[i + 1].x) / 2,
        y: (pts[i].y + pts[i + 1].y) / 2)
      path.addQuadCurve(to: mid, control: pts[i])
    }
    path.addLine(to: pts.last!)
    return path
  }

  /// Renders the Apple Silent preset as a dashed accent-colored guide
  /// showing roughly what macOS governs when the user curve is off. The
  /// `opacity` parameter drives the crossfade from active to inactive.
  private func drawGhostCurve(context: GraphicsContext, size: CGSize, opacity: Double) {
    guard opacity > 0.01 else { return }
    let ghostPoints = CurvePresets.appleSilent.curvePoints()
    let pathPoints = CurveInterpolation.pathPoints(
      points: ghostPoints, mode: .catmullRom,
      tempRange: tempRange, steps: 300)
    guard !pathPoints.isEmpty else { return }

    let pixelPoints = pathPoints.map { dataToPixel(temp: $0.0, percent: $0.1, in: size) }
    let line = smoothedPath(through: pixelPoints)
    context.stroke(
      line,
      with: .color(curveColor.opacity(0.75 * opacity)),
      style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round, dash: [5, 4]))
  }

  // MARK: - Hover Tooltip

  private func drawHoverLine(context: GraphicsContext, size: CGSize) {
    guard let mouse = mouseLocation else { return }
    guard draggedIndex == nil, hoveredIndex == nil else { return }
    let data = pixelToData(mouse, in: size)
    guard data.x >= tempRange.lowerBound, data.x <= tempRange.upperBound else { return }

    let percent = model.evaluate(at: data.x)
    let pos = dataToPixel(temp: data.x, percent: percent, in: size)
    let plotTop = topPad
    let plotBottom = size.height - bottomPad

    var vLine = Path()
    vLine.move(to: CGPoint(x: pos.x, y: plotTop))
    vLine.addLine(to: CGPoint(x: pos.x, y: plotBottom))
    context.stroke(vLine, with: .color(Color.primary.opacity(0.08)), lineWidth: 0.5)

    let dotRect = CGRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8)
    context.fill(Circle().path(in: dotRect), with: .color(curveColor.opacity(0.6)))

    // Tooltip text and pill are rendered outside of Canvas by
    // `hoverTooltipOverlay`. This keeps the pill position animatable.
    _ = plotTop
    _ = plotBottom
    _ = percent
    _ = pos
  }

  /// "System Default" pill placed just below the ghost line in the open
  /// triangle under the rising portion of the curve. Fades with
  /// activePhase so it only shows when Fan Control is off. Uses the
  /// same pill treatment as the Now label.
  @ViewBuilder
  private func appleAutoLabelOverlay(size: CGSize) -> some View {
    let inverse = 1.0 - activePhase
    if inverse > 0.01 {
      // Anchor at the midpoint of the rising ramp, offset slightly
      // below the line so it sits in the open area beneath the dash.
      let ghostAt = CurveInterpolation.evaluate(
        at: 92,
        points: CurvePresets.appleSilent.curvePoints(),
        mode: .catmullRom)
      let anchor = dataToPixel(temp: 92, percent: ghostAt, in: size)
      let text = Text("System Default")
        .font(.system(.caption2, design: .rounded).weight(.medium))
        .foregroundColor(curveColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)

      Group {
        if #available(macOS 26.0, *) {
          text.glassEffect(in: RoundedRectangle(cornerRadius: 4))
        } else {
          text
            .background(
              RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(
              RoundedRectangle(cornerRadius: 4)
                .stroke(curveColor.opacity(0.35), lineWidth: 0.5))
        }
      }
      .opacity(inverse)
      .position(x: anchor.x - 34, y: anchor.y + 16)
      .allowsHitTesting(false)
    }
  }

  /// "Now" label with Liquid Glass on macOS 26, plain background below.
  @ViewBuilder
  private var nowLabel: some View {
    let text = Text("Now")
      .font(.system(.caption2, design: .rounded).weight(.medium))
      .foregroundColor(Color(nsColor: .systemOrange))
      .padding(.horizontal, 5)
      .padding(.vertical, 1)

    if #available(macOS 26.0, *) {
      text.glassEffect(in: RoundedRectangle(cornerRadius: 3))
    } else {
      text
        .background(
          RoundedRectangle(cornerRadius: 3)
            .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 3)
            .stroke(Color(nsColor: .systemOrange).opacity(0.35), lineWidth: 0.5)
        )
    }
  }

  @ViewBuilder
  private var pressureLabel: some View {
    let text = Text("Pressure")
      .font(.system(.caption2, design: .rounded).weight(.medium))
      .foregroundColor(Color(nsColor: .systemOrange).opacity(0.78))
      .padding(.horizontal, 5)
      .padding(.vertical, 1)

    if #available(macOS 26.0, *) {
      text.glassEffect(in: RoundedRectangle(cornerRadius: 3))
    } else {
      text
        .background(
          RoundedRectangle(cornerRadius: 3)
            .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 3)
            .stroke(Color(nsColor: .systemOrange).opacity(0.22), lineWidth: 0.5)
        )
    }
  }

  /// Tooltip pill with Liquid Glass when available.
  @ViewBuilder
  private func tooltipPill(temp: Double, percent: Double, rpm: Int) -> some View {
    let label = Text("\(displayTemp(temp))\(unit.symbol)  \(Int(percent * 100))%  \(rpm.formatted()) RPM")
      .font(.system(.caption2, design: .rounded).weight(.medium))
      .foregroundColor(Color.primary.opacity(0.95))
      .padding(.horizontal, 7)
      .padding(.vertical, 3)

    if #available(macOS 26.0, *) {
      label.glassEffect(in: RoundedRectangle(cornerRadius: 5))
    } else {
      label
        .background(
          RoundedRectangle(cornerRadius: 5)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 5)
            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
  }

  /// Tooltip rendered as a real SwiftUI view so its .position animates
  /// between frames instead of snapping on every mouse sample.
  @ViewBuilder
  private func hoverTooltipOverlay(size: CGSize) -> some View {
    if let mouse = mouseLocation, draggedIndex == nil, hoveredIndex == nil {
      let data = pixelToData(mouse, in: size)
      if data.x >= tempRange.lowerBound, data.x <= tempRange.upperBound {
        let percent = model.evaluate(at: data.x)
        let pos = dataToPixel(temp: data.x, percent: percent, in: size)
        let rpm = Int(rpmRange.min + Float(percent) * (rpmRange.max - rpmRange.min))
        let tooltipY = pos.y > topPad + 32 ? pos.y - 26 : pos.y + 26

        // Only show the tooltip when the mouse is close to (or below) the
        // curve line. Far above it the user is not actually probing the
        // curve and a floating pill just adds noise.
        let distanceFromCurve = mouse.y - pos.y
        let showTooltip = distanceFromCurve > -30

        if showTooltip {
          tooltipPill(temp: data.x, percent: percent, rpm: rpm)
            .position(x: pos.x, y: tooltipY)
            .animation(.easeOut(duration: 0.12), value: pos)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
      }
    }
  }

  // MARK: - Control Points

  @ViewBuilder
  private func controlPointsOverlay(size: CGSize) -> some View {
    ForEach(Array(model.controlPoints.enumerated()), id: \.element.id) { index, point in
      controlPointView(index: index, point: point, size: size)
    }
  }

  private func controlPointView(index: Int, point: CurvePoint, size: CGSize) -> some View {
    let pos = dataToPixel(temp: point.temperature, percent: point.fanPercent, in: size)
    let isHighlighted = hoveredIndex == index || draggedIndex == index

    let strokeColor: Color = model.isActive ? curveColor : Color.secondary
    return Circle()
      .fill(Color(nsColor: .textBackgroundColor))
      .frame(width: isHighlighted ? 14 : 10, height: isHighlighted ? 14 : 10)
      .overlay(Circle().stroke(strokeColor, lineWidth: isHighlighted ? 2.5 : 1.5))
      .shadow(color: strokeColor.opacity(0.25), radius: isHighlighted ? 6 : 2)
      .position(pos)
      .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHighlighted)
      .animation(.easeInOut(duration: 0.35), value: model.isActive)
      .gesture(dragGesture(index: index, size: size))
  }

  // MARK: - Gestures

  private func dragGesture(index: Int, size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        draggedIndex = index
        hoveredIndex = index
        var data = pixelToData(value.location, in: size)
        data.x = max(tempRange.lowerBound, min(tempRange.upperBound, data.x))
        data.y = max(0, min(1, data.y))

        if index == 0 || index == model.controlPoints.count - 1 {
          data.x = model.controlPoints[index].temperature
        }

        applyDraggedPoint(at: index, temperature: data.x, proposedPercent: data.y)
      }
      .onEnded { value in
        draggedIndex = nil
        hoveredIndex = hoveredControlPointIndex(at: value.location, in: size)
      }
  }

  private func hoveredControlPointIndex(at location: CGPoint, in size: CGSize) -> Int? {
    model.controlPoints.enumerated()
      .compactMap { index, point -> (index: Int, distance: CGFloat)? in
        let pos = dataToPixel(temp: point.temperature, percent: point.fanPercent, in: size)
        let distance = hypot(pos.x - location.x, pos.y - location.y)
        guard distance <= controlPointHitRadius else { return nil }
        return (index, distance)
      }
      .min { lhs, rhs in lhs.distance < rhs.distance }?
      .index
  }

  private func startMarkerSmoothing() {
    markerSmoothingTask?.cancel()
    lastMarkerUpdateTime = nil
    markerSmoothingTask = Task { @MainActor in
      let clock = ContinuousClock()
      while !Task.isCancelled {
        let now = clock.now
        let deltaSeconds: Double
        if let lastMarkerUpdateTime {
          deltaSeconds = Double(lastMarkerUpdateTime.duration(to: now).components.seconds)
            + Double(lastMarkerUpdateTime.duration(to: now).components.attoseconds) / 1e18
        } else {
          deltaSeconds = Double(markerSmoothingInterval) / 1e9
        }
        self.lastMarkerUpdateTime = now

        displayedCommittedTemperature = exponentiallyApproach(
          current: displayedCommittedTemperature,
          target: targetCommittedTemperature,
          deltaSeconds: deltaSeconds,
          halfLife: committedMarkerTemperatureHalfLife
        )
        displayedCommittedPercent = exponentiallyApproach(
          current: displayedCommittedPercent,
          target: targetCommittedPercent,
          deltaSeconds: deltaSeconds,
          halfLife: committedMarkerPercentHalfLife
        )
        displayedRawTemperature = exponentiallyApproach(
          current: displayedRawTemperature,
          target: targetRawTemperature,
          deltaSeconds: deltaSeconds,
          halfLife: rawMarkerTemperatureHalfLife
        )
        displayedRawPercent = exponentiallyApproach(
          current: displayedRawPercent,
          target: targetRawPercent,
          deltaSeconds: deltaSeconds,
          halfLife: rawMarkerPercentHalfLife
        )
        try? await Task.sleep(nanoseconds: markerSmoothingInterval)
      }
    }
  }

  private func exponentiallyApproach(
    current: Double,
    target: Double,
    deltaSeconds: Double,
    halfLife: Double
  ) -> Double {
    guard halfLife > 0, deltaSeconds > 0 else { return target }
    let decay = pow(0.5, deltaSeconds / halfLife)
    let next = target + (current - target) * decay
    return abs(next - target) < 0.0001 ? target : next
  }

  /// Direct point dragging preserves a non-decreasing curve while
  /// smoothly pulling nearby neighbors. Immediate neighbors move most;
  /// farther points move less, then the whole set reclamps into a valid
  /// monotonic shape.
  private func applyDraggedPoint(at index: Int, temperature: Double, proposedPercent: Double) {
    let originalPoints = model.controlPoints
    let originalPercent = originalPoints[index].fanPercent
    let leftConstraint = index > 0 ? originalPoints[index - 1].fanPercent : 0.0
    let rightConstraint = index < originalPoints.count - 1 ? originalPoints[index + 1].fanPercent : 1.0
    let clampedPercent = max(leftConstraint, min(rightConstraint, proposedPercent))
    let delta = clampedPercent - originalPercent
    let adjustedTemperatures = adjustedTemperaturesForDrag(
      originalPoints: originalPoints,
      draggedIndex: index,
      proposedTemperature: temperature)

    for pointIndex in model.controlPoints.indices {
      model.controlPoints[pointIndex].temperature = adjustedTemperatures[pointIndex]
    }
    model.controlPoints[index].fanPercent = clampedPercent

    for earlierIndex in stride(from: index - 1, through: 0, by: -1) {
      let distance = Double(index - earlierIndex)
      let weight = percentInfluenceWeight(distance: distance)
      let desired = originalPoints[earlierIndex].fanPercent + delta * weight
      let ceiling = model.controlPoints[earlierIndex + 1].fanPercent
      model.controlPoints[earlierIndex].fanPercent = max(0.0, min(ceiling, desired))
    }

    for laterIndex in (index + 1)..<model.controlPoints.count {
      let distance = Double(laterIndex - index)
      let weight = percentInfluenceWeight(distance: distance)
      let desired = originalPoints[laterIndex].fanPercent + delta * weight
      let floor = model.controlPoints[laterIndex - 1].fanPercent
      model.controlPoints[laterIndex].fanPercent = max(floor, min(1.0, desired))
    }

    smoothPercentsAroundDraggedPoint(index: index)
  }

  private func percentInfluenceWeight(distance: Double) -> Double {
    pow(0.55, max(0, distance - 1))
  }

  private func temperatureInfluenceWeight(distance: Double) -> Double {
    if distance <= 1 { return 0.72 }
    return 0.72 * pow(0.32, distance - 1)
  }

  private func adjustedTemperaturesForDrag(
    originalPoints: [CurvePoint],
    draggedIndex: Int,
    proposedTemperature: Double
  ) -> [Double] {
    var temperatures = originalPoints.map(\.temperature)
    let delta = proposedTemperature - originalPoints[draggedIndex].temperature
    guard draggedIndex > 0, draggedIndex < originalPoints.count - 1 else {
      temperatures[draggedIndex] = originalPoints[draggedIndex].temperature
      return temperatures
    }

    let globalMin = originalPoints.first?.temperature ?? tempRange.lowerBound
    let globalMax = originalPoints.last?.temperature ?? tempRange.upperBound
    let lowerBound =
      globalMin + Double(draggedIndex) * minimumPointSpacing
    let upperBound =
      globalMax - Double(originalPoints.count - draggedIndex - 1) * minimumPointSpacing
    temperatures[draggedIndex] = max(lowerBound, min(upperBound, proposedTemperature))

    for earlierIndex in stride(from: draggedIndex - 1, through: 1, by: -1) {
      let distance = Double(draggedIndex - earlierIndex)
      let desired =
        originalPoints[earlierIndex].temperature
        + delta * temperatureInfluenceWeight(distance: distance)
      let maxTemp = temperatures[earlierIndex + 1] - minimumPointSpacing
      let minTemp = globalMin + Double(earlierIndex) * minimumPointSpacing
      temperatures[earlierIndex] = max(minTemp, min(maxTemp, desired))
    }

    for laterIndex in (draggedIndex + 1)..<(originalPoints.count - 1) {
      let distance = Double(laterIndex - draggedIndex)
      let desired =
        originalPoints[laterIndex].temperature
        + delta * temperatureInfluenceWeight(distance: distance)
      let minTemp = temperatures[laterIndex - 1] + minimumPointSpacing
      let maxTemp = globalMax - Double(originalPoints.count - laterIndex - 1) * minimumPointSpacing
      temperatures[laterIndex] = max(minTemp, min(maxTemp, desired))
    }

    temperatures[0] = globalMin
    temperatures[temperatures.count - 1] = globalMax

    for pointIndex in 1..<temperatures.count {
      temperatures[pointIndex] = max(
        temperatures[pointIndex],
        temperatures[pointIndex - 1] + minimumPointSpacing)
    }
    for pointIndex in stride(from: temperatures.count - 2, through: 0, by: -1) {
      temperatures[pointIndex] = min(
        temperatures[pointIndex],
        temperatures[pointIndex + 1] - minimumPointSpacing)
    }

    return temperatures
  }

  private func smoothPercentsAroundDraggedPoint(index: Int) {
    guard model.controlPoints.count > 2 else { return }

    let currentPercents = model.controlPoints.map(\.fanPercent)
    var smoothedPercents = currentPercents

    for pointIndex in 1..<(model.controlPoints.count - 1) where pointIndex != index {
      let left = currentPercents[pointIndex - 1]
      let right = currentPercents[pointIndex + 1]
      let interpolated = (left + right) / 2
      let distance = Double(abs(pointIndex - index))
      let smoothingStrength = 0.38 * pow(0.45, max(0, distance - 1))
      smoothedPercents[pointIndex] =
        currentPercents[pointIndex]
        + (interpolated - currentPercents[pointIndex]) * smoothingStrength
    }

    smoothedPercents[index] = currentPercents[index]
    smoothedPercents[0] = currentPercents[0]
    smoothedPercents[smoothedPercents.count - 1] = currentPercents[smoothedPercents.count - 1]

    for pointIndex in 1..<smoothedPercents.count {
      smoothedPercents[pointIndex] = max(
        smoothedPercents[pointIndex],
        smoothedPercents[pointIndex - 1])
    }
    for pointIndex in stride(from: smoothedPercents.count - 2, through: 0, by: -1) {
      smoothedPercents[pointIndex] = min(
        smoothedPercents[pointIndex],
        smoothedPercents[pointIndex + 1])
    }

    for pointIndex in model.controlPoints.indices {
      model.controlPoints[pointIndex].fanPercent = max(0.0, min(1.0, smoothedPercents[pointIndex]))
    }
  }

  // MARK: - Coordinate Mapping

  private func dataToPixel(temp: Double, percent: Double, in size: CGSize) -> CGPoint {
    let w = size.width - leftPad - rightPad
    let h = size.height - topPad - bottomPad
    let clampedTemp = max(tempRange.lowerBound, min(tempRange.upperBound, temp))
    let clampedPercent = max(0, min(1, percent))
    let x =
      leftPad
      + CGFloat((clampedTemp - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound)) * w
    let y = topPad + CGFloat(1 - clampedPercent) * h
    return CGPoint(x: x, y: y)
  }

  private func pixelToData(_ pt: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
    let w = size.width - leftPad - rightPad
    let h = size.height - topPad - bottomPad
    let temp =
      tempRange.lowerBound + Double((pt.x - leftPad) / w)
      * (tempRange.upperBound - tempRange.lowerBound)
    let percent = 1.0 - Double((pt.y - topPad) / h)
    return (temp, percent)
  }
}

/// A straight dashed line shape that fills its frame along the given axis.
/// Using a Shape instead of a `Path` literal lets the surrounding `.position`
/// modifier animate the line smoothly as the anchor point changes.
private struct DashedLine: Shape {
  enum Axis { case horizontal, vertical }
  let axis: Axis

  func path(in rect: CGRect) -> Path {
    var p = Path()
    switch axis {
    case .horizontal:
      let y = rect.midY
      p.move(to: CGPoint(x: rect.minX, y: y))
      p.addLine(to: CGPoint(x: rect.maxX, y: y))
    case .vertical:
      let x = rect.midX
      p.move(to: CGPoint(x: x, y: rect.minY))
      p.addLine(to: CGPoint(x: x, y: rect.maxY))
    }
    return p
  }
}
