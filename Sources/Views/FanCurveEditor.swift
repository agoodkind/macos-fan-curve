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

  private let margin: CGFloat = 50
  private let tempRange: ClosedRange<Double> = 20...110

  var body: some View {
    GeometryReader { geo in
      let size = geo.size

      ZStack {
        Canvas { context, canvasSize in
          drawGrid(context: context, size: canvasSize)
          drawCurve(context: context, size: canvasSize)
          drawCurrentPosition(context: context, size: canvasSize)
        }

        // Draggable control points
        ForEach(Array(model.controlPoints.enumerated()), id: \.element.id) { index, point in
          let pos = dataToPixel(temp: point.temperature, percent: point.fanPercent, in: size)
          Circle()
            .fill(.white)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2.5))
            .shadow(color: .accentColor.opacity(0.4), radius: 4)
            .position(pos)
            .gesture(
              DragGesture(minimumDistance: 0)
                .onChanged { value in
                  var data = pixelToData(value.location, in: size)
                  data.x = max(tempRange.lowerBound, min(tempRange.upperBound, data.x))
                  data.y = max(0, min(1, data.y))

                  // Lock first/last X
                  if index == 0 { data.x = model.controlPoints[index].temperature }
                  if index == model.controlPoints.count - 1 {
                    data.x = model.controlPoints[index].temperature
                  }

                  // Monotonicity
                  if index > 0 {
                    data.x = max(model.controlPoints[index - 1].temperature + 1, data.x)
                  }
                  if index < model.controlPoints.count - 1 {
                    data.x = min(model.controlPoints[index + 1].temperature - 1, data.x)
                  }

                  model.controlPoints[index].temperature = data.x
                  model.controlPoints[index].fanPercent = data.y
                }
                .onEnded { _ in
                  model.save()
                }
            )
        }
      }
    }
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  // MARK: - Drawing

  private func drawGrid(context: GraphicsContext, size: CGSize) {
    let gridColor = Color.gray.opacity(0.2)
    let labelColor = Color.secondary

    // Vertical lines (temperature)
    for temp in stride(from: 20.0, through: 110.0, by: 10.0) {
      let x = dataToPixel(temp: temp, percent: 0, in: size).x
      var path = Path()
      path.move(to: CGPoint(x: x, y: margin))
      path.addLine(to: CGPoint(x: x, y: size.height - margin))
      context.stroke(path, with: .color(gridColor), lineWidth: 0.5)

      if Int(temp) % 20 == 0 {
        context.draw(
          Text("\(Int(temp))C").font(.system(size: 10)).foregroundColor(labelColor),
          at: CGPoint(x: x, y: size.height - margin + 15))
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
        context.draw(
          Text("\(Int(pct * 100))%").font(.system(size: 10)).foregroundColor(labelColor),
          at: CGPoint(x: margin - 20, y: y))
      }
    }
  }

  private func drawCurve(context: GraphicsContext, size: CGSize) {
    let pathPoints = CurveInterpolation.pathPoints(
      points: model.controlPoints, mode: model.interpolationMode,
      tempRange: tempRange, steps: 200)

    guard !pathPoints.isEmpty else { return }

    // Fill under curve
    var fillPath = Path()
    let firstPt = dataToPixel(temp: pathPoints[0].0, percent: pathPoints[0].1, in: size)
    fillPath.move(to: CGPoint(x: firstPt.x, y: dataToPixel(temp: 20, percent: 0, in: size).y))
    fillPath.addLine(to: firstPt)
    for point in pathPoints.dropFirst() {
      let pt = dataToPixel(temp: point.0, percent: point.1, in: size)
      fillPath.addLine(to: pt)
    }
    let lastPt = dataToPixel(
      temp: pathPoints.last!.0, percent: pathPoints.last!.1, in: size)
    fillPath.addLine(to: CGPoint(x: lastPt.x, y: dataToPixel(temp: 20, percent: 0, in: size).y))
    fillPath.closeSubpath()

    context.fill(
      fillPath,
      with: .linearGradient(
        Gradient(colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.05)]),
        startPoint: CGPoint(x: 0, y: margin),
        endPoint: CGPoint(x: 0, y: size.height - margin)))

    // Curve line
    var linePath = Path()
    linePath.move(to: firstPt)
    for point in pathPoints.dropFirst() {
      let pt = dataToPixel(temp: point.0, percent: point.1, in: size)
      linePath.addLine(to: pt)
    }
    context.stroke(linePath, with: .color(.accentColor), lineWidth: 2.5)
  }

  private func drawCurrentPosition(context: GraphicsContext, size: CGSize) {
    let temp = sensorState.governingTemperature
    guard temp > 0 else { return }

    let percent = model.evaluate(at: temp)
    let pos = dataToPixel(temp: temp, percent: percent, in: size)

    // Crosshair
    let crossSize: CGFloat = 8
    var hLine = Path()
    hLine.move(to: CGPoint(x: pos.x - crossSize, y: pos.y))
    hLine.addLine(to: CGPoint(x: pos.x + crossSize, y: pos.y))
    context.stroke(hLine, with: .color(.red), lineWidth: 1.5)

    var vLine = Path()
    vLine.move(to: CGPoint(x: pos.x, y: pos.y - crossSize))
    vLine.addLine(to: CGPoint(x: pos.x, y: pos.y + crossSize))
    context.stroke(vLine, with: .color(.red), lineWidth: 1.5)

    // Dot
    let dotRect = CGRect(x: pos.x - 5, y: pos.y - 5, width: 10, height: 10)
    context.fill(Circle().path(in: dotRect), with: .color(.red))

    // Label
    context.draw(
      Text("\(Int(temp))C / \(Int(percent * 100))%")
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.red),
      at: CGPoint(x: pos.x, y: pos.y - 16))
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
