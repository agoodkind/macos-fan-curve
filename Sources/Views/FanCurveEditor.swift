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

  // Animated current position
  @State private var animatedTemp: Double = 0
  @State private var animatedPercent: Double = 0

  private let margin: CGFloat = 64
  private let tempRange: ClosedRange<Double> = 20...110
  private let curveColor = Color(nsColor: .systemCyan)

  private var rpmRange: (min: Float, max: Float) {
    guard let fan = sensorState.fans.first else { return (0, 8000) }
    return (fan.minRPM, fan.maxRPM)
  }

  var body: some View {
    GeometryReader { geo in
      let size = geo.size

      ZStack {
        Canvas { context, canvasSize in
          drawGrid(context: context, size: canvasSize)
          drawCurve(context: context, size: canvasSize)
          drawHoverLine(context: context, size: canvasSize)
        }

        // Animated current position overlay (not in Canvas so it animates smoothly)
        currentPositionOverlay(size: size)

        controlPointsOverlay(size: size)
      }
      .onContinuousHover { phase in
        switch phase {
        case .active(let location): mouseLocation = location
        case .ended: mouseLocation = nil
        }
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.05)))
    .onChange(of: sensorState.governingTemperature) { newTemp in
      withAnimation(.easeInOut(duration: 0.8)) {
        animatedTemp = newTemp
        animatedPercent = model.evaluate(at: newTemp)
      }
    }
  }

  // MARK: - Current Position (SwiftUI overlay for smooth animation)

  @ViewBuilder
  private func currentPositionOverlay(size: CGSize) -> some View {
    if animatedTemp > 0 {
      let pos = dataToPixel(temp: animatedTemp, percent: animatedPercent, in: size)
      let rpm = Int(rpmRange.min + Float(animatedPercent) * (rpmRange.max - rpmRange.min))
      let zeroY = dataToPixel(temp: 20, percent: 0, in: size).y

      // Dashed vertical line
      Path { path in
        path.move(to: CGPoint(x: pos.x, y: pos.y + 8))
        path.addLine(to: CGPoint(x: pos.x, y: zeroY))
      }
      .stroke(Color(nsColor: .systemOrange).opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

      // Glowing dot
      Circle()
        .fill(Color(nsColor: .systemOrange))
        .frame(width: 10, height: 10)
        .shadow(color: Color(nsColor: .systemOrange).opacity(0.5), radius: 6)
        .position(pos)

      // Label with background for readability
      Text("\(Int(animatedTemp))°C  \(rpm) RPM")
        .font(.system(.caption, design: .monospaced).weight(.medium))
        .foregroundColor(Color(nsColor: .systemOrange))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .position(x: pos.x, y: pos.y - 20)
    }
  }

  // MARK: - Grid

  private func drawGrid(context: GraphicsContext, size: CGSize) {
    let gridColor = Color.primary.opacity(0.035)
    let labelColor = Color.primary.opacity(0.25)

    for temp in stride(from: 20.0, through: 110.0, by: 10.0) {
      let x = dataToPixel(temp: temp, percent: 0, in: size).x
      var path = Path()
      path.move(to: CGPoint(x: x, y: margin))
      path.addLine(to: CGPoint(x: x, y: size.height - margin))
      context.stroke(path, with: .color(gridColor), lineWidth: 0.5)

      if Int(temp) % 20 == 0 {
        context.draw(
          Text("\(Int(temp))°").font(.system(.caption2, design: .monospaced)).foregroundColor(labelColor),
          at: CGPoint(x: x, y: size.height - margin + 16))
      }
    }

    for pct in stride(from: 0.0, through: 1.0, by: 0.1) {
      let y = dataToPixel(temp: 20, percent: pct, in: size).y
      var path = Path()
      path.move(to: CGPoint(x: margin, y: y))
      path.addLine(to: CGPoint(x: size.width - margin, y: y))
      context.stroke(path, with: .color(gridColor), lineWidth: 0.5)

      if Int(pct * 100) % 20 == 0 {
        let rpm = Int(rpmRange.min + Float(pct) * (rpmRange.max - rpmRange.min))
        context.draw(
          Text("\(Int(pct * 100))%").font(.system(.caption2, design: .monospaced)).foregroundColor(labelColor),
          at: CGPoint(x: margin - 22, y: y - 6))
        context.draw(
          Text("\(rpm)").font(.system(size: 9, weight: .light, design: .monospaced)).foregroundColor(labelColor.opacity(0.6)),
          at: CGPoint(x: margin - 22, y: y + 6))
      }
    }
  }

  // MARK: - Curve

  private func drawCurve(context: GraphicsContext, size: CGSize) {
    let pathPoints = CurveInterpolation.pathPoints(
      points: model.controlPoints, mode: model.interpolationMode,
      tempRange: tempRange, steps: 300)
    guard !pathPoints.isEmpty else { return }

    let firstPt = dataToPixel(temp: pathPoints[0].0, percent: pathPoints[0].1, in: size)
    let zeroY = dataToPixel(temp: 20, percent: 0, in: size).y

    // Fill
    var fillPath = Path()
    fillPath.move(to: CGPoint(x: firstPt.x, y: zeroY))
    fillPath.addLine(to: firstPt)
    for point in pathPoints.dropFirst() {
      fillPath.addLine(to: dataToPixel(temp: point.0, percent: point.1, in: size))
    }
    let lastPt = dataToPixel(temp: pathPoints.last!.0, percent: pathPoints.last!.1, in: size)
    fillPath.addLine(to: CGPoint(x: lastPt.x, y: zeroY))
    fillPath.closeSubpath()

    context.fill(
      fillPath,
      with: .linearGradient(
        Gradient(colors: [curveColor.opacity(0.1), curveColor.opacity(0.005)]),
        startPoint: CGPoint(x: 0, y: margin),
        endPoint: CGPoint(x: 0, y: size.height - margin)))

    // Glow
    var linePath = Path()
    linePath.move(to: firstPt)
    for point in pathPoints.dropFirst() {
      linePath.addLine(to: dataToPixel(temp: point.0, percent: point.1, in: size))
    }
    context.stroke(
      linePath, with: .color(curveColor.opacity(0.12)),
      style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))

    // Main line
    context.stroke(
      linePath, with: .color(curveColor),
      style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
  }

  // MARK: - Hover

  private func drawHoverLine(context: GraphicsContext, size: CGSize) {
    guard let mouse = mouseLocation else { return }
    let data = pixelToData(mouse, in: size)
    guard data.x >= tempRange.lowerBound, data.x <= tempRange.upperBound else { return }

    let percent = model.evaluate(at: data.x)
    let curvePos = dataToPixel(temp: data.x, percent: percent, in: size)

    // Vertical line following mouse
    var line = Path()
    line.move(to: CGPoint(x: curvePos.x, y: margin))
    line.addLine(to: CGPoint(x: curvePos.x, y: size.height - margin))
    context.stroke(line, with: .color(Color.primary.opacity(0.06)), lineWidth: 0.5)

    // Horizontal line to Y axis
    var hLine = Path()
    hLine.move(to: CGPoint(x: margin, y: curvePos.y))
    hLine.addLine(to: CGPoint(x: curvePos.x, y: curvePos.y))
    context.stroke(hLine, with: .color(Color.primary.opacity(0.04)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))

    // Dot on curve
    let dotRect = CGRect(x: curvePos.x - 4, y: curvePos.y - 4, width: 8, height: 8)
    context.fill(Circle().path(in: dotRect), with: .color(curveColor.opacity(0.5)))

    // Tooltip follows the curve
    let rpm = Int(rpmRange.min + Float(percent) * (rpmRange.max - rpmRange.min))
    let tooltipY = curvePos.y > margin + 40 ? curvePos.y - 20 : curvePos.y + 20
    context.draw(
      Text("\(Int(data.x))°C  \(Int(percent * 100))%  \(rpm) RPM")
        .font(.system(.caption, design: .monospaced).weight(.medium))
        .foregroundColor(Color.primary.opacity(0.55)),
      at: CGPoint(x: curvePos.x, y: tooltipY))
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
    let rpm = Int(rpmRange.min + Float(point.fanPercent) * (rpmRange.max - rpmRange.min))

    return ZStack {
      if isHovered {
        tooltipView(temp: Int(point.temperature), percent: Int(point.fanPercent * 100), rpm: rpm)
          .offset(y: -30)
      }

      Circle()
        .fill(Color(nsColor: .windowBackgroundColor))
        .frame(width: isHovered ? 14 : 10, height: isHovered ? 14 : 10)
        .overlay(Circle().stroke(curveColor, lineWidth: isHovered ? 2.5 : 1.5))
        .shadow(color: curveColor.opacity(0.3), radius: isHovered ? 8 : 3)
    }
    .position(pos)
    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
    .onHover { over in hoveredIndex = over ? index : nil }
    .gesture(dragGesture(index: index, size: size))
  }

  @ViewBuilder
  private func tooltipView(temp: Int, percent: Int, rpm: Int) -> some View {
    let text = Text("\(temp)° / \(percent)% / \(rpm) RPM")
      .font(.system(.caption, design: .monospaced))
      .padding(.horizontal, 10)
      .padding(.vertical, 6)

    if #available(macOS 26.0, *) {
      text
        .glassEffect(.regular, in: .capsule)
    } else {
      text
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
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
      .onEnded { _ in model.save() }
  }

  // MARK: - Coordinate Mapping

  private func dataToPixel(temp: Double, percent: Double, in size: CGSize) -> CGPoint {
    let w = size.width - margin * 2
    let h = size.height - margin * 2
    let x = margin + CGFloat((temp - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound)) * w
    let y = margin + CGFloat(1 - percent) * h
    return CGPoint(x: x, y: y)
  }

  private func pixelToData(_ pt: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
    let w = size.width - margin * 2
    let h = size.height - margin * 2
    let temp = tempRange.lowerBound + Double((pt.x - margin) / w) * (tempRange.upperBound - tempRange.lowerBound)
    let percent = 1.0 - Double((pt.y - margin) / h)
    return (temp, percent)
  }
}
