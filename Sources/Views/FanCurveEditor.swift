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
          drawCurrentPosition(context: context, size: canvasSize)
        }

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
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06)))
    .onAppear {
      // Default to smooth curves
      if model.interpolationMode == .linear {
        model.interpolationMode = .catmullRom
        model.save()
      }
    }
  }

  // MARK: - Grid

  private func drawGrid(context: GraphicsContext, size: CGSize) {
    let gridColor = Color.primary.opacity(0.04)
    let labelColor = Color.primary.opacity(0.3)

    for temp in stride(from: 20.0, through: 110.0, by: 10.0) {
      let x = dataToPixel(temp: temp, percent: 0, in: size).x
      var path = Path()
      path.move(to: CGPoint(x: x, y: margin))
      path.addLine(to: CGPoint(x: x, y: size.height - margin))
      context.stroke(path, with: .color(gridColor), lineWidth: 0.5)

      if Int(temp) % 20 == 0 {
        context.draw(
          Text("\(Int(temp))°")
            .font(.system(size: 9, weight: .light, design: .monospaced))
            .foregroundColor(labelColor),
          at: CGPoint(x: x, y: size.height - margin + 14))
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
        let label = "\(Int(pct * 100))%  \(rpm)"
        context.draw(
          Text(label)
            .font(.system(size: 8, weight: .light, design: .monospaced))
            .foregroundColor(labelColor),
          at: CGPoint(x: margin - 28, y: y))
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

    // Gradient fill
    var fillPath = Path()
    fillPath.move(to: CGPoint(x: firstPt.x, y: zeroY))
    fillPath.addLine(to: firstPt)
    for point in pathPoints.dropFirst() {
      fillPath.addLine(to: dataToPixel(temp: point.0, percent: point.1, in: size))
    }
    let lastPt = dataToPixel(temp: pathPoints.last!.0, percent: pathPoints.last!.1, in: size)
    fillPath.addLine(to: CGPoint(x: lastPt.x, y: zeroY))
    fillPath.closeSubpath()

    let curveColor = Color(nsColor: .systemCyan)
    context.fill(
      fillPath,
      with: .linearGradient(
        Gradient(colors: [curveColor.opacity(0.12), curveColor.opacity(0.01)]),
        startPoint: CGPoint(x: 0, y: margin),
        endPoint: CGPoint(x: 0, y: size.height - margin)))

    // Glow line (wider, faint)
    var glowPath = Path()
    glowPath.move(to: firstPt)
    for point in pathPoints.dropFirst() {
      glowPath.addLine(to: dataToPixel(temp: point.0, percent: point.1, in: size))
    }
    context.stroke(
      glowPath, with: .color(curveColor.opacity(0.15)),
      style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))

    // Main curve line
    context.stroke(
      glowPath, with: .color(curveColor),
      style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
  }

  // MARK: - Current Position

  private func drawCurrentPosition(context: GraphicsContext, size: CGSize) {
    let temp = sensorState.governingTemperature
    guard temp > 0 else { return }

    let percent = model.evaluate(at: temp)
    let pos = dataToPixel(temp: temp, percent: percent, in: size)

    // Subtle vertical line
    let zeroY = dataToPixel(temp: 20, percent: 0, in: size).y
    var vLine = Path()
    vLine.move(to: CGPoint(x: pos.x, y: pos.y))
    vLine.addLine(to: CGPoint(x: pos.x, y: zeroY))
    context.stroke(vLine, with: .color(Color.primary.opacity(0.08)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

    // Small dot
    let dotRect = CGRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8)
    context.fill(Circle().path(in: dotRect), with: .color(Color(nsColor: .systemOrange)))
    let outerRect = CGRect(x: pos.x - 6, y: pos.y - 6, width: 12, height: 12)
    context.stroke(Circle().path(in: outerRect), with: .color(Color(nsColor: .systemOrange).opacity(0.3)), lineWidth: 2)

    // Minimal label
    let rpm = Int(rpmRange.min + Float(percent) * (rpmRange.max - rpmRange.min))
    context.draw(
      Text("\(Int(temp))° \(rpm) RPM")
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundColor(Color(nsColor: .systemOrange).opacity(0.8)),
      at: CGPoint(x: pos.x, y: pos.y - 14))
  }

  // MARK: - Hover

  private func drawHoverLine(context: GraphicsContext, size: CGSize) {
    guard let mouse = mouseLocation, hoveredIndex == nil else { return }
    let data = pixelToData(mouse, in: size)
    guard data.x >= tempRange.lowerBound, data.x <= tempRange.upperBound else { return }

    let percent = model.evaluate(at: data.x)
    let curvePos = dataToPixel(temp: data.x, percent: percent, in: size)

    var line = Path()
    line.move(to: CGPoint(x: mouse.x, y: margin))
    line.addLine(to: CGPoint(x: mouse.x, y: size.height - margin))
    context.stroke(line, with: .color(Color.primary.opacity(0.06)), lineWidth: 0.5)

    let dotRect = CGRect(x: curvePos.x - 3, y: curvePos.y - 3, width: 6, height: 6)
    context.fill(Circle().path(in: dotRect), with: .color(Color(nsColor: .systemCyan).opacity(0.5)))

    let rpm = Int(rpmRange.min + Float(percent) * (rpmRange.max - rpmRange.min))
    context.draw(
      Text("\(Int(data.x))° \(Int(percent * 100))% \(rpm)")
        .font(.system(size: 9, weight: .light, design: .monospaced))
        .foregroundColor(Color.primary.opacity(0.4)),
      at: CGPoint(x: curvePos.x, y: curvePos.y - 12))
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
    let curveColor = Color(nsColor: .systemCyan)

    return ZStack {
      if isHovered {
        Circle()
          .fill(curveColor.opacity(0.1))
          .frame(width: 32, height: 32)

        Text("\(Int(point.temperature))° / \(Int(point.fanPercent * 100))% / \(rpm) RPM")
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(.ultraThinMaterial)
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .offset(y: -26)
      }

      Circle()
        .fill(Color(nsColor: .windowBackgroundColor))
        .frame(width: isHovered ? 14 : 10, height: isHovered ? 14 : 10)
        .overlay(Circle().stroke(curveColor, lineWidth: isHovered ? 2.5 : 2))
        .shadow(color: curveColor.opacity(0.4), radius: isHovered ? 8 : 4)
    }
    .position(pos)
    .animation(.easeOut(duration: 0.15), value: isHovered)
    .onHover { over in
      hoveredIndex = over ? index : nil
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
