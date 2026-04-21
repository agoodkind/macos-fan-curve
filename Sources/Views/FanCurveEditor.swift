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
  @ObservedObject var sensorState: SensorState
  @State private var hoveredIndex: Int?
  @State private var mouseLocation: CGPoint?
  @State private var draggedCurveID: UUID?
  @State private var segmentDrag: SegmentDragState?

  /// State captured when the user starts dragging on a curve segment so
  /// both bracketing control points move together by the drag delta in
  /// both temperature (x) and fan percent (y).
  private struct SegmentDragState {
    let leftIndex: Int
    let leftInitialTemp: Double
    let leftInitialPercent: Double
    let rightInitialTemp: Double
    let rightInitialPercent: Double
    let startTemp: Double
    let startPercent: Double
  }

  @AppStorage("temperatureUnit") private var unitRaw: String = "celsius"

  private var unit: TemperatureUnit {
    TemperatureUnit(rawValue: unitRaw) ?? .celsius
  }

  private func displayTemp(_ celsius: Double) -> Int {
    Int(unit.convert(fromCelsius: celsius).rounded())
  }

  @State private var animatedTemp: Double = 0
  @State private var animatedActualPercent: Double = 0
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

  private let tempRange: ClosedRange<Double> = 20...110
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
    guard let fan = sensorState.fans.first else { return (0, 8000) }
    let minR: Float = underdriveEnabled ? 0 : fan.minRPM
    let maxR: Float = overdriveEnabled ? max(fan.maxRPM, overdriveTargetRPM) : fan.maxRPM
    return (minR, maxR)
  }

  /// Average actual RPM across all fans. Used to plot the live "actual" dot.
  private var averageFanRPM: Float {
    let fans = sensorState.fans
    guard !fans.isEmpty else { return 0 }
    return fans.reduce(0) { $0 + $1.actualRPM } / Float(fans.count)
  }

  /// Where the fan actually is, expressed as a 0...1 value inside the
  /// reported min-max RPM range. Zero RPM maps to zero regardless of min.
  private var currentActualPercent: Double {
    let rpm = averageFanRPM
    if rpm <= 0 { return 0 }
    let span = rpmRange.max - rpmRange.min
    guard span > 0 else { return 0 }
    let p = Double((rpm - rpmRange.min) / span)
    return max(0, min(1, p))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
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
          .gesture(addPointDragGesture(size: size))

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
          case .active(let location): mouseLocation = location
          case .ended: mouseLocation = nil
          }
        }
      }
    }
    .fancurveGlassCard(cornerRadius: 12)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .onAppear { activePhase = model.isActive ? 1.0 : 0.0 }
    .onChange(of: model.isActive) { newActive in
      withAnimation(.easeInOut(duration: 0.35)) {
        activePhase = newActive ? 1.0 : 0.0
      }
    }
    .onChange(of: sensorState.governingTemperature) { newTemp in
      withAnimation(.easeInOut(duration: 0.8)) {
        animatedTemp = newTemp
        animatedActualPercent = currentActualPercent
      }
    }
    .onChange(of: averageFanRPM) { _ in
      withAnimation(.easeInOut(duration: 0.8)) {
        animatedActualPercent = currentActualPercent
      }
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
    if animatedTemp > 0 {
      let actualPos = dataToPixel(temp: animatedTemp, percent: animatedActualPercent, in: size)
      let curveTargetPercent = model.evaluate(at: animatedTemp)
      let curvePos = dataToPixel(temp: animatedTemp, percent: curveTargetPercent, in: size)
      let plotLeft = leftPad
      let zeroY = dataToPixel(temp: 20, percent: 0, in: size).y
      let dashLine = StrokeStyle(lineWidth: 1, dash: [4, 4])

      // Vertical dashed line from the actual dot down to the X axis.
      // Uses a Shape with explicit height so .position() animates smoothly
      // alongside the orange dot when the temperature changes.
      DashedLine(axis: .vertical)
        .stroke(Color(nsColor: .systemOrange).opacity(0.25), style: dashLine)
        .frame(width: 1, height: max(0, zeroY - actualPos.y))
        .position(x: actualPos.x, y: (actualPos.y + zeroY) / 2)

      // Horizontal dashed line from the Y axis to the actual dot.
      // Balances the vertical guide and surfaces the current fan percent.
      DashedLine(axis: .horizontal)
        .stroke(Color(nsColor: .systemOrange).opacity(0.25), style: dashLine)
        .frame(width: max(0, actualPos.x - plotLeft), height: 1)
        .position(x: (plotLeft + actualPos.x) / 2, y: actualPos.y)

      // Curve target marker: hollow ring on the curve at current temperature.
      // Shows where the curve would put the fan right now.
      Circle()
        .stroke(Color(nsColor: .systemOrange).opacity(0.55), lineWidth: 1.5)
        .frame(width: 9, height: 9)
        .position(curvePos)

      // Actual marker: solid dot at current (temp, actual RPM).
      // Shows where the fan really is.
      Circle()
        .fill(Color(nsColor: .systemOrange))
        .frame(width: 10, height: 10)
        .shadow(color: Color(nsColor: .systemOrange).opacity(0.5), radius: 6)
        .position(actualPos)

      if mouseLocation == nil {
        nowLabel
          .position(x: actualPos.x, y: actualPos.y - 16)
      }
    }
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
    if model.isActive {
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
    for temp in stride(from: 20.0, through: 110.0, by: 10.0) {
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
    if let mouse = mouseLocation {
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
    let isHovered = hoveredIndex == index

    let strokeColor: Color = model.isActive ? curveColor : Color.secondary
    return Circle()
      .fill(Color(nsColor: .textBackgroundColor))
      .frame(width: isHovered ? 14 : 10, height: isHovered ? 14 : 10)
      .overlay(Circle().stroke(strokeColor, lineWidth: isHovered ? 2.5 : 1.5))
      .shadow(color: strokeColor.opacity(0.25), radius: isHovered ? 6 : 2)
      .position(pos)
      .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
      .animation(.easeInOut(duration: 0.35), value: model.isActive)
      .onHover { over in hoveredIndex = over ? index : nil }
      .gesture(dragGesture(index: index, size: size))
  }

  // MARK: - Gestures

  private func dragGesture(index: Int, size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        var data = pixelToData(value.location, in: size)
        data.x = max(tempRange.lowerBound, min(tempRange.upperBound, data.x))
        data.y = max(0, min(1, data.y))

        if index == 0 { data.x = model.controlPoints[index].temperature }
        if index == model.controlPoints.count - 1 {
          data.x = model.controlPoints[index].temperature
        }
        if index > 0 {
          data.x = max(model.controlPoints[index - 1].temperature + 1, data.x)
        }
        if index < model.controlPoints.count - 1 {
          data.x = min(model.controlPoints[index + 1].temperature - 1, data.x)
        }

        // Enforce a non-decreasing curve. Cannot dip below the left
        // neighbor (hard clamp). Rising above the right neighbor pushes
        // every later point up to match, so dragging an early point to
        // 100% lifts the tail instead of being blocked.
        var minY = 0.0
        if index > 0 { minY = model.controlPoints[index - 1].fanPercent }
        data.y = max(minY, min(1.0, data.y))

        model.controlPoints[index].temperature = data.x
        model.controlPoints[index].fanPercent = data.y
        for laterIndex in (index + 1)..<model.controlPoints.count {
          if model.controlPoints[laterIndex].fanPercent < data.y {
            model.controlPoints[laterIndex].fanPercent = data.y
          } else {
            break
          }
        }
        hoveredIndex = index
      }
  }

  /// Drag on a segment between two control points to yank both of them
  /// vertically together. No new points are inserted. If the drag starts
  /// outside the temperature range of any segment (before the first or
  /// after the last point), the gesture is ignored.
  private func addPointDragGesture(size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        let data = pixelToData(value.location, in: size)

        if segmentDrag == nil {
          guard let leftIdx = leftBracketIndex(forTemp: data.x) else { return }
          let left = model.controlPoints[leftIdx]
          let right = model.controlPoints[leftIdx + 1]
          segmentDrag = SegmentDragState(
            leftIndex: leftIdx,
            leftInitialTemp: left.temperature,
            leftInitialPercent: left.fanPercent,
            rightInitialTemp: right.temperature,
            rightInitialPercent: right.fanPercent,
            startTemp: data.x,
            startPercent: max(0, min(1, data.y)))
        }

        guard let drag = segmentDrag else { return }
        let currentPercent = max(0, min(1, data.y))
        let deltaY = currentPercent - drag.startPercent
        let deltaX = data.x - drag.startTemp

        // Parameter t along the segment at the original grab point.
        // t=0 means grabbed at the left vertex, t=1 at the right. Each
        // endpoint moves proportionally so the endpoint closer to the
        // grab shifts more, giving rope-pull physics.
        let span = drag.rightInitialTemp - drag.leftInitialTemp
        let t: Double =
          span > 0
          ? max(0, min(1, (drag.startTemp - drag.leftInitialTemp) / span))
          : 0.5
        let leftWeight = 1 - t
        let rightWeight = t

        // Clamp horizontal motion so the pair does not cross its
        // neighbors or leave the plot. Each endpoint has its own bound.
        let leftMinTemp = drag.leftIndex > 0
          ? model.controlPoints[drag.leftIndex - 1].temperature + 1
          : tempRange.lowerBound
        let rightMaxTemp = (drag.leftIndex + 2) < model.controlPoints.count
          ? model.controlPoints[drag.leftIndex + 2].temperature - 1
          : tempRange.upperBound

        var newLeftTemp = drag.leftInitialTemp + leftWeight * deltaX
        var newRightTemp = drag.rightInitialTemp + rightWeight * deltaX
        newLeftTemp = max(leftMinTemp, newLeftTemp)
        newRightTemp = min(rightMaxTemp, newRightTemp)
        // Never let the two endpoints collide or swap.
        if newLeftTemp >= newRightTemp - 0.5 {
          let mid = (newLeftTemp + newRightTemp) / 2
          newLeftTemp = mid - 0.5
          newRightTemp = mid + 0.5
        }

        // Honor monotonicity: left endpoint cannot drop below its
        // outer-left neighbor (hard clamp). Right endpoint is free to
        // rise above its outer-right neighbor because later points get
        // cascaded up after the write. The pair itself never swaps.
        let leftMinPct = drag.leftIndex > 0
          ? model.controlPoints[drag.leftIndex - 1].fanPercent
          : 0.0

        var newLeftPct = max(leftMinPct, min(1, drag.leftInitialPercent + leftWeight * deltaY))
        var newRightPct = max(0.0, min(1.0, drag.rightInitialPercent + rightWeight * deltaY))
        if newLeftPct > newRightPct {
          let mid = (newLeftPct + newRightPct) / 2
          newLeftPct = mid
          newRightPct = mid
        }

        model.controlPoints[drag.leftIndex].temperature = newLeftTemp
        model.controlPoints[drag.leftIndex].fanPercent = newLeftPct
        model.controlPoints[drag.leftIndex + 1].temperature = newRightTemp
        model.controlPoints[drag.leftIndex + 1].fanPercent = newRightPct

        // Cascade upward: any later point lower than the newly-raised
        // right endpoint gets lifted to match, stopping at the first
        // already-higher point.
        for laterIndex in (drag.leftIndex + 2)..<model.controlPoints.count {
          if model.controlPoints[laterIndex].fanPercent < newRightPct {
            model.controlPoints[laterIndex].fanPercent = newRightPct
          } else {
            break
          }
        }
      }
      .onEnded { _ in segmentDrag = nil }
  }

  /// Returns the index of the left bracketing control point for a given
  /// temperature. If temp falls before the first point, returns the
  /// first segment (0); if after the last, returns the last segment.
  /// This way the user can grab and drag any part of the plot, not just
  /// the span between the outermost control points.
  private func leftBracketIndex(forTemp temp: Double) -> Int? {
    let points = model.controlPoints
    guard points.count >= 2 else { return nil }
    if temp <= points.first!.temperature { return 0 }
    if temp >= points.last!.temperature { return points.count - 2 }
    for i in 0..<(points.count - 1) {
      if temp >= points[i].temperature, temp <= points[i + 1].temperature {
        return i
      }
    }
    return nil
  }

  // MARK: - Coordinate Mapping

  private func dataToPixel(temp: Double, percent: Double, in size: CGSize) -> CGPoint {
    let w = size.width - leftPad - rightPad
    let h = size.height - topPad - bottomPad
    let x =
      leftPad
      + CGFloat((temp - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound)) * w
    let y = topPad + CGFloat(1 - percent) * h
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
