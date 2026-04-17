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

  @State private var animatedTemp: Double = 0
  @State private var animatedActualPercent: Double = 0

  private let topPad: CGFloat = 40
  private let bottomPad: CGFloat = 44
  private let leftPad: CGFloat = 72
  private let rightPad: CGFloat = 24

  private let tempRange: ClosedRange<Double> = 20...110
  private let curveColor = Color.accentColor

  private var rpmRange: (min: Float, max: Float) {
    guard let fan = sensorState.fans.first else { return (0, 8000) }
    return (fan.minRPM, fan.maxRPM)
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
      header
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)

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

          currentPositionOverlay(size: size)
          controlPointsOverlay(size: size)
          hoverTooltipOverlay(size: size)
        }
        .onContinuousHover { phase in
          switch phase {
          case .active(let location): mouseLocation = location
          case .ended: mouseLocation = nil
          }
        }
      }
    }
    .background(Color(nsColor: .textBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
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

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Fan Curve")
          .font(.headline)
        Text(
          model.isActive
            ? "Fans are following this curve"
            : "Preview only. Turn on Fan Control to apply."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer()
      statusBadge
    }
  }

  @ViewBuilder
  private var statusBadge: some View {
    let (label, color): (String, Color) =
      model.isActive
      ? ("Applied", Color(nsColor: .systemGreen))
      : ("Preview", .secondary)
    Text(label)
      .font(.system(.caption2, design: .rounded).weight(.semibold))
      .foregroundColor(color)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(Capsule().fill(color.opacity(0.12)))
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
        Text("Now")
          .font(.system(.caption2, design: .rounded).weight(.medium))
          .foregroundColor(Color(nsColor: .systemOrange))
          .position(x: actualPos.x + 24, y: actualPos.y)
      }
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
        let text = Text("\(Int(temp))°C")
          .font(.system(.caption2, design: .rounded))
          .foregroundColor(labelColor)
        context.draw(text, at: CGPoint(x: x, y: plotBottom + 14), anchor: .center)
      }
    }
  }

  private func drawAxisTitles(context: GraphicsContext, size: CGSize) {
    let titleColor = Color.secondary.opacity(0.8)

    let xTitle = Text("Temperature (°C)")
      .font(.system(.caption2, design: .rounded).weight(.medium))
      .foregroundColor(titleColor)
    context.draw(
      xTitle,
      at: CGPoint(x: (leftPad + size.width - rightPad) / 2, y: size.height - 12),
      anchor: .center)

    let yTitle = Text("Fan Speed (% / RPM)")
      .font(.system(.caption2, design: .rounded).weight(.medium))
      .foregroundColor(titleColor)
    context.draw(
      yTitle,
      at: CGPoint(x: 8, y: topPad - 18),
      anchor: .leading)
  }

  // MARK: - Curve

  private func drawCurve(context: GraphicsContext, size: CGSize) {
    let pathPoints = CurveInterpolation.pathPoints(
      points: model.controlPoints, mode: model.interpolationMode,
      tempRange: tempRange, steps: 300)
    guard !pathPoints.isEmpty else { return }

    let firstPt = dataToPixel(temp: pathPoints[0].0, percent: pathPoints[0].1, in: size)
    let zeroY = dataToPixel(temp: 20, percent: 0, in: size).y

    var fill = Path()
    fill.move(to: CGPoint(x: firstPt.x, y: zeroY))
    fill.addLine(to: firstPt)
    for point in pathPoints.dropFirst() {
      fill.addLine(to: dataToPixel(temp: point.0, percent: point.1, in: size))
    }
    let lastPt = dataToPixel(temp: pathPoints.last!.0, percent: pathPoints.last!.1, in: size)
    fill.addLine(to: CGPoint(x: lastPt.x, y: zeroY))
    fill.closeSubpath()

    let active = model.isActive
    let fillOpacity = active ? 0.18 : 0.06
    let lineOpacity = active ? 1.0 : 0.6
    let glowOpacity = active ? 0.15 : 0.0

    context.fill(
      fill,
      with: .linearGradient(
        Gradient(colors: [curveColor.opacity(fillOpacity), curveColor.opacity(0.0)]),
        startPoint: CGPoint(x: 0, y: topPad),
        endPoint: CGPoint(x: 0, y: size.height - bottomPad)))

    var line = Path()
    line.move(to: firstPt)
    for point in pathPoints.dropFirst() {
      line.addLine(to: dataToPixel(temp: point.0, percent: point.1, in: size))
    }

    let lineStyle: StrokeStyle =
      active
      ? StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
      : StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round, dash: [6, 5])

    if glowOpacity > 0 {
      context.stroke(
        line, with: .color(curveColor.opacity(glowOpacity)),
        style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
    }
    context.stroke(
      line, with: .color(curveColor.opacity(lineOpacity)), style: lineStyle)
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

        Text("\(Int(data.x))°C  \(Int(percent * 100))%  \(rpm.formatted()) RPM")
          .font(.system(.caption2, design: .rounded).weight(.medium))
          .foregroundColor(Color.primary.opacity(0.95))
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(
            RoundedRectangle(cornerRadius: 5)
              .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
          )
          .overlay(
            RoundedRectangle(cornerRadius: 5)
              .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
          )
          .position(x: pos.x, y: tooltipY)
          .animation(.easeOut(duration: 0.12), value: pos)
          .transition(.opacity)
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

    return Circle()
      .fill(Color(nsColor: .textBackgroundColor))
      .frame(width: isHovered ? 14 : 10, height: isHovered ? 14 : 10)
      .overlay(Circle().stroke(curveColor, lineWidth: isHovered ? 2.5 : 1.5))
      .shadow(color: curveColor.opacity(0.25), radius: isHovered ? 6 : 2)
      .position(pos)
      .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
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

        model.controlPoints[index].temperature = data.x
        model.controlPoints[index].fanPercent = data.y
        hoveredIndex = index
      }
  }

  /// Drag anywhere on the plot area to create a new control point and move it.
  /// The gesture only fires when the user starts dragging on the canvas
  /// outside the existing handle hit targets.
  private func addPointDragGesture(size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        if draggedCurveID == nil {
          insertPoint(at: value.location, size: size)
        }
        guard
          let id = draggedCurveID,
          let idx = model.controlPoints.firstIndex(where: { $0.id == id })
        else { return }

        var data = pixelToData(value.location, in: size)
        data.x = max(tempRange.lowerBound, min(tempRange.upperBound, data.x))
        data.y = max(0, min(1, data.y))

        if idx > 0 {
          data.x = max(model.controlPoints[idx - 1].temperature + 1, data.x)
        }
        if idx < model.controlPoints.count - 1 {
          data.x = min(model.controlPoints[idx + 1].temperature - 1, data.x)
        }
        model.controlPoints[idx].temperature = data.x
        model.controlPoints[idx].fanPercent = data.y
      }
      .onEnded { _ in draggedCurveID = nil }
  }

  private func insertPoint(at pixel: CGPoint, size: CGSize) {
    let data = pixelToData(pixel, in: size)
    guard data.x > tempRange.lowerBound, data.x < tempRange.upperBound else { return }
    let point = CurvePoint(
      temperature: data.x,
      fanPercent: max(0, min(1, data.y)))
    model.controlPoints.append(point)
    model.controlPoints.sort { $0.temperature < $1.temperature }
    draggedCurveID = point.id
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
