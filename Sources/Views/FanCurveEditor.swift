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

  private let margin: CGFloat = 50
  private let tempRange: ClosedRange<Double> = 20...110

  // Use first fan's RPM range for display
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
          drawCurrentPosition(context: context, size: canvasSize)
          drawHoverLine(context: context, size: canvasSize)
        }

        // Draggable control points
        controlPointsOverlay(size: size)
      }
      .onContinuousHover { phase in
        switch phase {
        case .active(let location):
          mouseLocation = location
        case .ended:
          mouseLocation = nil
        }
      }
    }
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.15))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 0.5))
  }

  // MARK: - Drawing

  private func drawGrid(context: GraphicsContext, size: CGSize) {
    let gridColor = Color.primary.opacity(0.06)
    let labelColor = Color.secondary.opacity(0.7)

    // Vertical lines (temperature)
    for temp in stride(from: 20.0, through: 110.0, by: 10.0) {
      let x = dataToPixel(temp: temp, percent: 0, in: size).x
      var path = Path()
      path.move(to: CGPoint(x: x, y: margin))
      path.addLine(to: CGPoint(x: x, y: size.height - margin))
      context.stroke(path, with: .color(gridColor), lineWidth: 0.5)

      if Int(temp) % 20 == 0 {
        context.draw(
          Text("\(Int(temp))C")
            .font(.system(size: 9, design: .rounded))
            .foregroundColor(labelColor),
          at: CGPoint(x: x, y: size.height - margin + 14))
      }
    }

    // Horizontal lines (fan %)
    for pct in stride(from: 0.0, through: 1.0, by: 0.1) {
      let y = dataToPixel(temp: 20, percent: pct, in: size).y
      var path = Path()
      path.move(to: CGPoint(x: margin, y: y))
      path.addLine(to: CGPoint(x: size.width - margin, y: y))
      context.stroke(path, with: .color(gridColor), lineWidth: 0.5)

      if Int(pct * 100) % 20 == 0 {
        let rpm = Int(rpmRange.min + Float(pct) * (rpmRange.max - rpmRange.min))
        context.draw(
          Text("\(Int(pct * 100))%")
            .font(.system(size: 9, design: .rounded))
            .foregroundColor(labelColor),
          at: CGPoint(x: margin - 18, y: y))
        context.draw(
          Text("\(rpm)")
            .font(.system(size: 8, design: .rounded))
            .foregroundColor(labelColor.opacity(0.5)),
          at: CGPoint(x: margin - 18, y: y + 10))
      }
    }

    // Axis labels
    context.draw(
      Text("Temperature")
        .font(.system(size: 9, weight: .medium, design: .rounded))
        .foregroundColor(labelColor),
      at: CGPoint(x: size.width / 2, y: size.height - 8))
  }

  private func drawCurve(context: GraphicsContext, size: CGSize) {
    let pathPoints = CurveInterpolation.pathPoints(
      points: model.controlPoints, mode: model.interpolationMode,
      tempRange: tempRange, steps: 200)

    guard !pathPoints.isEmpty else { return }

    let firstPt = dataToPixel(temp: pathPoints[0].0, percent: pathPoints[0].1, in: size)
    let zeroY = dataToPixel(temp: 20, percent: 0, in: size).y

    // Fill under curve
    var fillPath = Path()
    fillPath.move(to: CGPoint(x: firstPt.x, y: zeroY))
    fillPath.addLine(to: firstPt)
    for point in pathPoints.dropFirst() {
      fillPath.addLine(to: dataToPixel(temp: point.0, percent: point.1, in: size))
    }
    let lastPt = dataToPixel(
      temp: pathPoints.last!.0, percent: pathPoints.last!.1, in: size)
    fillPath.addLine(to: CGPoint(x: lastPt.x, y: zeroY))
    fillPath.closeSubpath()

    context.fill(
      fillPath,
      with: .linearGradient(
        Gradient(colors: [.accentColor.opacity(0.2), .accentColor.opacity(0.02)]),
        startPoint: CGPoint(x: 0, y: margin),
        endPoint: CGPoint(x: 0, y: size.height - margin)))

    // Curve line
    var linePath = Path()
    linePath.move(to: firstPt)
    for point in pathPoints.dropFirst() {
      linePath.addLine(to: dataToPixel(temp: point.0, percent: point.1, in: size))
    }
    context.stroke(
      linePath,
      with: .color(.accentColor),
      style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
  }

  private func drawCurrentPosition(context: GraphicsContext, size: CGSize) {
    let temp = sensorState.governingTemperature
    guard temp > 0 else { return }

    let percent = model.evaluate(at: temp)
    let pos = dataToPixel(temp: temp, percent: percent, in: size)

    // Vertical line from position to X axis
    var vLine = Path()
    vLine.move(to: CGPoint(x: pos.x, y: pos.y))
    vLine.addLine(to: CGPoint(x: pos.x, y: dataToPixel(temp: 20, percent: 0, in: size).y))
    context.stroke(vLine, with: .color(.red.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

    // Dot with glow
    let outerRect = CGRect(x: pos.x - 8, y: pos.y - 8, width: 16, height: 16)
    context.fill(Circle().path(in: outerRect), with: .color(.red.opacity(0.15)))
    let dotRect = CGRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8)
    context.fill(Circle().path(in: dotRect), with: .color(.red))

    // Label
    let rpm = Int(rpmRange.min + Float(percent) * (rpmRange.max - rpmRange.min))
    context.draw(
      Text("\(Int(temp))C  \(Int(percent * 100))%  \(rpm) RPM")
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .foregroundColor(.red),
      at: CGPoint(x: pos.x, y: pos.y - 14))
  }

  private func drawHoverLine(context: GraphicsContext, size: CGSize) {
    guard let mouse = mouseLocation, hoveredIndex == nil else { return }
    let data = pixelToData(mouse, in: size)
    guard data.x >= tempRange.lowerBound, data.x <= tempRange.upperBound else { return }

    let percent = model.evaluate(at: data.x)
    let curvePos = dataToPixel(temp: data.x, percent: percent, in: size)

    // Vertical hover line
    var line = Path()
    line.move(to: CGPoint(x: mouse.x, y: margin))
    line.addLine(to: CGPoint(x: mouse.x, y: size.height - margin))
    context.stroke(line, with: .color(.primary.opacity(0.1)), lineWidth: 0.5)

    // Dot on curve
    let dotRect = CGRect(x: curvePos.x - 3, y: curvePos.y - 3, width: 6, height: 6)
    context.fill(Circle().path(in: dotRect), with: .color(.accentColor.opacity(0.5)))

    // Hover tooltip
    let rpm = Int(rpmRange.min + Float(percent) * (rpmRange.max - rpmRange.min))
    context.draw(
      Text("\(Int(data.x))C / \(Int(percent * 100))% / \(rpm) RPM")
        .font(.system(size: 9, design: .rounded))
        .foregroundColor(.secondary),
      at: CGPoint(x: curvePos.x, y: curvePos.y - 12))
  }

  // MARK: - Control Points Overlay

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
    let lineWidth: CGFloat = isHovered ? 3 : 2
    let shadowRadius: CGFloat = isHovered ? 6 : 3

    return ZStack {
      if isHovered {
        Circle()
          .fill(Color.accentColor.opacity(0.2))
          .frame(width: 28, height: 28)

        Text("\(Int(point.temperature))C / \(Int(point.fanPercent * 100))% / \(rpm) RPM")
          .font(.system(size: 10, weight: .medium, design: .rounded))
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(.ultraThinMaterial)
          .clipShape(RoundedRectangle(cornerRadius: 4))
          .offset(y: -24)
      }

      Circle()
        .fill(.white)
        .frame(width: 12, height: 12)
        .overlay(Circle().stroke(Color.accentColor, lineWidth: lineWidth))
        .shadow(color: .accentColor.opacity(0.3), radius: shadowRadius)
    }
    .position(pos)
    .onHover { over in
      withAnimation(.easeInOut(duration: 0.15)) {
        hoveredIndex = over ? index : nil
      }
    }
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
      .onEnded { _ in
        model.save()
      }
  }

  // MARK: - Coordinate Mapping

  private func dataToPixel(temp: Double, percent: Double, in size: CGSize) -> CGPoint {
    let w = size.width - margin * 2
    let h = size.height - margin * 2
    let x =
      margin
      + CGFloat(
        (temp - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound)) * w
    let y = margin + CGFloat(1 - percent) * h
    return CGPoint(x: x, y: y)
  }

  private func pixelToData(_ pt: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
    let w = size.width - margin * 2
    let h = size.height - margin * 2
    let temp =
      tempRange.lowerBound
      + Double((pt.x - margin) / w) * (tempRange.upperBound - tempRange.lowerBound)
    let percent = 1.0 - Double((pt.y - margin) / h)
    return (temp, percent)
  }
}
